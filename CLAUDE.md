# Heraldr

Dispatch remote for herdr: the iOS app sends a request (typed,
dictated or pasted) to the `<slug>-main` Claude of a herdr workspace on
the Mac, over SSH, with no daemon on the Mac. Personal use, installed
directly on the iPhone.

- iOS: Swift 6 (strict concurrency), SwiftUI, iOS 26, XcodeGen project
- SSH: HeelerSSH package, pinned `Vendor/Heeler` submodule
- Mac: `mac/dispatch.sh` (send queue) and `mac/notify-hook.mjs` (herdr
  plugin that pushes questions to APNs), embedded in the app and
  reinstalled by it on every use

## Commands

```sh
bin/setup-ios                # Xcode, XcodeGen, Heeler submodule, pinned lint tools
bin/generate-ios             # ios/project.yml -> .xcodeproj, Heeler patches
bin/build-ios [simulator|device]
bin/run-ios [preset]         # worktree's simulator, on the fake Mac preset given
bin/ios-simulator            # udid of the worktree's simulator, created on first use
bin/run-ios-device [uuid]    # iPhone, signed with an App Store Connect key, OTA install off the LAN
bin/run-ios-tests [suite]    # app unit tests, then bin/run-mac-tests; fails on 0 tests or below the floor
bin/run-mac-tests            # dispatch.sh (fake herdr) and hook (fake APNs), no Xcode
bin/lint                     # shellcheck, swift-format, SwiftLint, Biome, guards (2 s)
bin/qa [--all|<class>...]    # UI tests touched by the diff on the fake Mac, light and dark screenshots
bin/local-ci                 # lint then tests (iOS skipped if the diff is docs only)
bin/local-ci push            # checks then push, no remote CI
bin/remove-worktree <name>   # after merge: processes, simulator, worktree, branch
```

Installing on the iPhone follows the global `ios-device-install` skill
(`devicectl` on the LAN, OTA through Tailscale elsewhere): over OTA,
`bin/run-ios-device` prints the URL to open in Safari on the iPhone.

Run long commands with an absolute path (`$PWD/bin/local-ci push`,
`$PWD/bin/run-ios-tests`): several worktrees run in parallel and the
command line must say which worktree it comes from. Only target a
process with `pkill -f` by that absolute path.

## Structure

```
ios/Heraldr/
├── App/        # HeraldrApp, AppModel (@Observable, screen state), AppEnvironment (injection)
├── Debug/      # FakeMac and its scenarios (#if DEBUG): AppModel tests, UI tests, QA
├── Dispatch/   # AgentName (slug), PromptEnvelope (instructions), Dispatcher (runs dispatch.sh), SendHistory
├── Herdr/      # HerdrClient: JSON API over herdr.sock, Workspace, Agent
├── Mac/        # MacTransport (protocol), MacLink (SSH actor, reconnection), PairedMac
├── Pairing/    # PairingCode (HERDR-PAIR:1), PairingCeremony, DeviceKey (Keychain)
├── Push/       # PushDevice, QuestionNotification, QuestionReply (shared with the extension), AppDelegate
├── Voice/      # Dictation (SpeechAnalyzer), TranscriptCleaner (Foundation Models), DictationLexicon, LexiconKeeper (backup on the Mac)
└── UI/
ios/HeraldrNotificationService/ # notification service extension: one action per option of a question
ios/HeraldrTests/   # Swift Testing
ios/HeraldrUITests/ # XCUITest on the fake Mac, one class per flow
mac/                # dispatch.sh, notify-hook.mjs
mac/test/           # dispatch_test.sh + fake-herdr, notify_hook_test.mjs, agent-names.tsv
```

## Code

- Every file or target goes through `ios/project.yml`; never edit the
  `.xcodeproj`, which is generated and ignored
- Do not touch `Vendor/Heeler` outside `Vendor/patches/`, applied by
  `bin/generate-ios`
- No comments, meaningful names; files end with a newline
- User-visible text in English
- All UI aims for a polished, minimalist look, in native iOS 26 Liquid
  Glass (`glassEffect`, `.glass` styles): few elements, no tinted
  capsule, icon or color that carries no information; check the
  rendering in light and dark (`docs/design.md`)
- The agent slug and the standard instructions exist in Swift and in
  `dispatch.sh` (Home relay): every change is made on both sides, the
  contract tests check it

## Tests

When to write a test: global policy (`~/.claude/CLAUDE.md`, Testing
section), no exception. Areas of this project where a bug is costly or
goes unnoticed, so to cover:

- app ↔ `dispatch.sh` contract: commands, arguments, tab-separated
  `status` output, duplicated agent name and instructions
  (`docs/spec.md` §8.2)
- send queue on the Mac: never send while the agent is working or
  blocked, order kept, `/clear` before each request, never an agent
  with the same name in another workspace
- Home routing: relay instructions, refusal to relay to Home
- pairing: expired code or code without bootstrap, enrollment
  response, pinned host key
- tolerant reading of the herdr API: unknown field or status
- notifications: hook (debounce, one notification per question, `-main`
  only, dead token), payload read by the app, token format
- shared vectors: `pairing-code-v1.json` (Heeler plugin) and
  `mac/test/agent-names.tsv` (app and `dispatch.sh`)

Boundaries to mock, and nothing else:

- herdr: `mac/test/fake-herdr` in the PATH, world described in files
- APNs: local HTTP/2 server (`HERALDR_APNS_ORIGIN`)
- SSH and Mac: `FakeMac` (`ios/Heraldr/Debug/`), conforming to
  `MacTransport`, scenario described as data (`FakeMacScenario`);
  `AppModel(environment: .fake(scenario, mac:, suiteName:))`
- real SSH: only the pinned host key test targets the Mac's sshd
  (`127.0.0.1:22`, Remote Login, a project prerequisite) and stops
  before any authentication
- Keychain, UserDefaults, Foundation Models, Speech, camera, clock:
  injection (`now:` of `PairingCeremony.pair`)
- never an app type (`Dispatcher`, `HerdrClient`, `AppModel`…)

Where to put a test:

- Mac behavior: `mac/test/dispatch_test.sh` (end to end of the script
  with `fake-herdr`) or `mac/test/notify_hook_test.mjs`
- app: `ios/HeraldrTests/`, Swift Testing, `@Suite` and `@Test`
  described by a business sentence in English; tests hosted in the
  app, so `Bundle.main` is the app's (embedded scripts)
- a contract shared between two sides goes through a vector file read
  by both, declared as a resource of `HeraldrTests` in `project.yml`

`AppModel` is tested through its public surface (`refresh`, `send`,
`resend`, `open`, `targetState`…) against `FakeMac`
(`ios/HeraldrTests/AppModelTests.swift`): notice, announced failure,
target, refresh. `FakeMac` is a double of the boundary, to evolve like
`dispatch.sh` and herdr when they change: it must never accept what
the real one refuses. The queue guarantees (workspace, order, waiting)
stay held and tested by `dispatch.sh`.

UI tests (`ios/HeraldrUITests/`, XCUITest): the app runs on the fake
Mac (`launch("<preset>")` or a JSON scenario in `HERALDR_FAKE_MAC`;
`HERALDR_FAKE_MAC_KEPT_FOR_RELAUNCH=1` keeps it for the next relaunch
only, the one from a tap on a notification with the app killed),
elements are targeted by `accessibilityIdentifier` (never by label;
every element a test targets gets one), and
`capture("<screen>", in: app)` keeps the screen in light and dark. A
new or changed flow has its UI test; a new state to show has its
preset in `FakeMacScenario`. Never a temporary patch of fake data.

A test that breaks with no intended behavior change: say whether the
test or the code is wrong, never adapt it silently.

End of iteration: `$PWD/bin/run-ios-tests` (or `bin/run-mac-tests` if
only the Mac scripts changed), the `verify-heraldr` skill if the UI or
the app changed, then `docs/spec.md` up to date. Lint runs on its
own: the project's Stop hook (`.claude/settings.json`) runs `bin/lint`
before handing back, and so does `bin/local-ci`.

Several worktrees running on the same simulator crash each other:
`bin/run-ios`, `bin/run-ios-tests` and `bin/qa` target by udid the
simulator of the worktree ("Heraldr <worktree>", `bin/ios-simulator`).
Never a shared simulator, never `booted`.

## Specification

**IMPORTANT**: `docs/spec.md` describes what the app does, screen by
screen, and its contract with the Mac. It is normative: a gap between
the spec and the code is resolved in favor of the spec.

Any behavior change of the app (`ios/Heraldr`) or of the Mac scripts
(`mac/dispatch.sh`, `mac/notify-hook.mjs`) MUST update the spec in the
same commit or the same PR: screen, state, rule, displayed text,
`dispatch.sh` command or output, payload, tolerance to an unknown
field. No gap between the spec and the code: a bug found is fixed in
the branch, with its test; if it really cannot be fixed right away,
the spec describes the actual behavior. `bin/lint` fails if a "Known
gaps" section reappears with content.

`bin/local-ci` warns (without blocking) when these paths changed since
`origin/main` without the spec. A refactoring with no visible effect
needs no update: say so in the PR.

The how goes in `docs/architecture.md`, the why and the rejected
options in `docs/decisions.md`.

## QA

QA is done by the agent with the `verify-heraldr` skill
(`.claude/skills/verify-heraldr/`): launch on the worktree's simulator
and the fake Mac, doctor, `bin/qa` and its screenshots, argent to
explore, then the `QA.md` boxes after an install on the iPhone.

## Git

- Commits, PRs, docs and test descriptions in English
- Push a branch with `$PWD/bin/local-ci push` rather than `git push`:
  it pushes HEAD with lease to the branch of the same name, sets the
  "Local CI" status to pending, runs the checks then sets it to
  success, failure (step that broke) or error (interruption); never on
  `main`
- `bin/local-ci` skips the iOS tests when the whole diff since the
  merge-base with `origin/main` is docs (`docs/`, `.claude/`, `*.md`
  outside `ios/` and `mac/`); a dirty worktree or an empty diff run
  everything

### Worktrees

Each topic goes in a dedicated worktree (`start` skill), under
`worktrees/` (ignored):

```sh
git worktree add worktrees/<name> -b feature/<name> origin/main
```

No setup script: `bin/generate-ios` initializes the Heeler submodule
and `bin/ios-simulator` creates the worktree's simulator on first use.
After merge, from the main checkout (`/cleanup` calls it):
`bin/remove-worktree <name>` stops the processes started from the
worktree, deletes its simulator, the worktree and its merged branch.

## Documentation

- `docs/spec.md`: normative app behavior and contract with the Mac
- `docs/architecture.md`: SSH, dispatch, queue, notifications
- `docs/decisions.md`: decision log
- `docs/toolchain.md`: scripts, signing, differences with Heeler
- `docs/risks.md`: spikes and verified points
- `docs/roadmap.md`, `docs/vision.md`, `docs/design.md`
- `QA.md`: what requires the real iPhone and the real Mac, 3 to 5
  boxes per iteration
