# Toolchain

Modeled on the `bin/*-ios` scripts of another of my iOS apps, with
XcodeGen added.

## Project

- `ios/project.yml` (XcodeGen) is versioned, the `.xcodeproj` is
  generated and ignored by git: no `.pbxproj` conflicts between agent
  worktrees
- dev bundle id: `HERALDR_BUNDLE_ID` (`ios/Signing.local.xcconfig`);
  the notification service extension embedded in the app is
  `$(HERALDR_BUNDLE_ID).notification-service`, its App ID and profile
  created by automatic signing like the app's
- automatic signing with a personal team, direct install on the iPhone
  (no TestFlight)

## Scripts

| Script | Role |
| --- | --- |
| `bin/setup-ios` | checks Xcode 26, xcode-select, XcodeGen, installs and checks the pinned tools (shellcheck 0.11.0, SwiftLint 0.65.1, Biome 2.5.15, xcbeautify 3.2.1, AXe 1.8.0; swift-format ships with Xcode), initializes the Heeler submodule |
| `bin/generate-ios` | `xcodegen generate`, applies `Vendor/patches/*.patch` to the submodule |
| `bin/build-ios [simulator\|device]` | build |
| `bin/ios-simulator [--boot\|--name\|--delete]` | prints the udid of the simulator dedicated to the worktree ("Heraldr <worktree>", iPhone SE 3rd generation, `QA_DEVICE_TYPE`), created on first use and recreated when its device type changes; `--delete` also stops the argent services driving it |
| `bin/run-ios [preset]` | build, install and launch on the worktree's simulator; with a fake Mac preset (`demo`, `history`, `question`...) or `HERALDR_FAKE_MAC=<json>`, the app runs on the fake Mac |
| `bin/run-ios-device [uuid]` | build then install on the iPhone through the global `ios-device-install` skill: `devicectl` when the iPhone is reachable, otherwise an OTA install page over Tailscale (waits while the device is busy, signs through `~/dotfiles/bin/with-ci-keychain`) |
| `bin/run-ios-tests [suite]` | unit tests on the worktree's simulator, full output through xcbeautify, warnings included, then `bin/run-mac-tests`; reads the `.xcresult` and fails if no test ran or, for the full suite, below the floor in `ios/minimum-test-count` (raise it as tests are added). UI tests do not run here |
| `bin/lint` | shellcheck (`.shellcheckrc`), `xcrun swift-format lint --strict` (`.swift-format`), SwiftLint CLI (`.swiftlint.yml`), Biome (`biome.json`), and two guards: `agent_status` read only for an agent, no filled-in "Known gaps" section in the spec; 2 s |
| `bin/qa [--all\|<class>...]` | runs the `HeraldrUITests` classes touched by the diff since `origin/main` on the worktree's simulator (status bar frozen at 9:41; xcodebuild shuts it down to clone it), against the fake Mac, and exports light and dark screenshots to `~/share/screenshots/<worktree>/`, on 3 clones in parallel (`QA_WORKERS`); 3 to 4 min for `--all` |
| `bin/run-mac-tests` | tests of the dispatch script (`mac/test/dispatch_test.sh`, fake herdr) and of the notification hook (`node --test mac/test/notify_hook_test.mjs`, fake APNs) |
| `bin/local-ci [push]` | `bin/lint` then all tests, iOS skipped if the diff since `origin/main` is docs only; `push` first pushes HEAD (with lease, never `main`), sets "Local CI" to pending on that commit, then to success, failure (failing step, HEAD or worktree changed during the run) or error (Ctrl-C, TERM, HUP); without `push`, no status |
| `bin/open-ios-xcode` | generates then opens the project |
| `bin/remove-worktree <name>` | after merge, from the main checkout (`/cleanup` calls it): stops the processes whose command line holds the worktree's path, deletes its simulator, removes the worktree, deletes its branch if merged |
| `bin/render-ios-icon` | regenerates AppIcon and logo from `docs/branding/logo/voice-and-lanes-*.svg` (rsvg-convert) |

`main` is protected on GitHub: the "Local CI" status must be success to
merge a PR, without requiring the branch to be up to date (`strict`
false, no rebase or new run when `main` has moved). Admins are exempt,
to keep direct tooling pushes to `main`. Applied with:

```sh
gh api -X PUT repos/skelz0r/heraldr/branches/main/protection --input - <<'JSON'
{"required_status_checks":{"strict":false,"checks":[{"context":"Local CI"}]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}
JSON
```

Observed environment: Xcode 26.2, macOS 26.4.1, iPhone 16 Pro
(reachable over Tailscale) with Apple Intelligence.

Push requires an explicit App ID, which the wildcard profile does not
cover. Team and bundle id come from `ios/Signing.xcconfig`
(`com.example` and no team by default), overridden by
`ios/Signing.local.xcconfig`, ignored:

```
DEVELOPMENT_TEAM = <team id>
HERALDR_BUNDLE_ID = <bundle id>
```

`bin/run-ios-device` reads `.env.local`, ignored: `IOS_DEVICE_UUID`
(CoreDevice UUID of the iPhone, `xcrun devicectl list devices`, can be
overridden by argument) and, without an Apple account in Xcode, the App
Store Connect API key that creates the App ID and profile (`ASC_KEY_ID`,
`ASC_KEY_ISSUER_ID`, `ASC_KEY_PATH`, by default
`~/.private_keys/AuthKey_<id>.p8`). `bin/generate-ios` copies both files
from the main checkout into a worktree that lacks them.

`devicectl` only sees the iPhone over USB or on the same LAN (Bonjour,
which does not cross Tailscale): elsewhere it lists it as `unavailable`
and the install used to fail ("unable to locate a device matching the
requested device identifier"). `bin/run-ios-device` therefore hands the
install to `~/.agents/skills/ios-device-install/scripts/install-ios-app`,
which then publishes the build at
`https://<mac>.<tailnet>.ts.net/ios-ota/<bundle id>/`, to open in
Safari on the iPhone. The dev profile already contains the iPhone's
UDID: no archive or export.

The build is signed through `~/dotfiles/bin/with-ci-keychain`, which
puts the CI keychain first and unlocks it, then restores the order. herdr
runs as a LaunchDaemon, outside the GUI session: `codesign` fails from its
tabs (`errSecInternalComponent`, `unable to build chain to self-signed
root`), so the wrapper re-runs `xcodebuild` through `ssh localhost`,
where signing works. Environment variables do not cross that hop, hence
the App Store Connect key passed as arguments. The install runs from
herdr directly.

Two differences with Heeler, which builds with Xcode 26.6:

- the Xcode 26.2 compiler wrongly raises a concurrency error in
  `SessionDriver.swift`; `Vendor/patches/` works around it, applied by
  `bin/generate-ios`, and the submodule ignores that change
- the xcframeworks have no x86_64 simulator slice, excluded from the
  simulator build

The `dev-ios` skill covers remote builds on another Mac if needed.

## Agent hook

`.claude/settings.json` declares a Stop hook: when the agent is about
to hand back, `.claude/hooks/lint-before-stop` runs `bin/lint` (2 s) if
the worktree is dirty or the branch is ahead of `origin/main`, and
exits with code 2 and the errors on stderr, which Claude Code sends back
to the agent so it fixes them before answering. Only one retry per turn
(`stop_hook_active`) so it never loops. No build, no tests.

## Simulator and screenshots

Every script that runs the app targets the worktree's simulator by udid
(`bin/ios-simulator`), never a shared simulator nor `booted`. Driving
it by hand, with argent, and the evidence: the `verify-heraldr` skill.

A simulator whose appearance was never switched to dark ignores the
appearance changes of the UI tests (every dark capture stays light),
even across reboots: one `xcrun simctl ui <udid> appearance dark` fixes
it for good, so `bin/qa` switches to dark then light before playing.
