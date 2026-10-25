---
name: verify-heraldr
description: Prove that a change to Heraldr works in the real app on this worktree's iOS simulator, against the fake Mac - launch, doctor, starting state (fake Mac presets), bin/qa on the UI tests the diff touches with light and dark screenshots, argent to explore what no UI test covers, evidence, cleanup - then the 3 to 5 QA.md boxes after an install on the iPhone. Use at the end of an iteration that touches the app or its UI, before saying a screen or flow is done, when asked to "vérifie dans l'app", "QA", "lance l'app sur le simulateur", "pilote le simulateur", or when a result on the simulator looks off.
---

# Verify Heraldr

The proof runs on the simulator dedicated to this worktree
("Heraldr <worktree>", an iPhone SE, the smallest iOS 26 screen),
created on first use by `bin/ios-simulator` and targeted by udid by
every script. Never a shared simulator, never `booted`: other worktrees
run their own at the same time.

The app always runs on the fake Mac (`FakeMac`, `#if DEBUG`): on the
paired Mac a send reaches a real Claude of a real herdr workspace.

## Launch

```sh
$PWD/bin/run-ios demo
```

Builds (about 60 s cold, 5 s incremental), boots the worktree's
simulator, installs and launches on the fake Mac preset given as
argument. Without argument the app talks to the paired Mac: never for a
QA. Presets (`FakeMacScenario.presets`): `demo`, `history`, `question`
(a notification arrives after 12 s), `unpaired`, `unreachable`,
`connecting`, `empty`. A whole scenario as JSON:
`HERALDR_FAKE_MAC='<json>' $PWD/bin/run-ios`. Usable when the doctor is
green, not when the build succeeded.

`bin/qa` and `bin/run-ios-tests` use the same simulator: `bin/qa`
shuts it down to clone it, and the app is no longer installed after
`bin/run-ios-tests`. Never drive the app while they run; relaunch with
`bin/run-ios` after them (the doctor says so).

## Doctor

```sh
.claude/skills/verify-heraldr/scripts/doctor
```

Read-only, under a second, one line per check, each failure followed by
its fix. Run it before driving and whenever a result looks off:

- Xcode selected (not the Command Line Tools)
- the worktree's simulator exists and is booted
- the app installed on it is the build of this worktree (binaries
  compared with `build/ios-run`), not another checkout's
- the build is newer than `ios/Heraldr`, `ios/project.yml` and `mac/`
- the running app is on the fake Mac (`-HeraldrFakeMac` or
  `HERALDR_FAKE_MAC` in its process), so no request leaves for a real
  Claude
- argent installed outside the repository, telemetry disabled
- argent reads the app's screen

## Starting state

No login: the fake Mac preset is the starting state. Home shows the
workspaces as tiles (`tile.<workspace id>`, `wA` is `~`, `wS` Acme,
blocked with a question in `question`), the target (`target.workspace`,
`target.state`, `target.next`) and the three sends (`home.write`,
`home.voice`, `home.paste`). The compose sheet holds `compose.text`,
`compose.target`, `compose.attach`, `compose.dictate`, `compose.send`,
`compose.close`; a send shows a transient `notice` (about 2 s).
History is `home.history`, settings `home.settings`, the Mac sheet
`home.mac`. A new state to show gets its preset in `FakeMacScenario`,
never a temporary patch of fake data.

## Proof, in this order

1. `$PWD/bin/qa` on the diff: plays the `HeraldrUITests` classes the
   diff touches (it prints them; `--all` for everything, 3 to 4 min on 3
   simulator clones), and exports the light and dark screenshots to
   `~/share/screenshots/<worktree>/`. Look at the 2 or 3 of the changed
   screens, in light and dark (`docs/design.md`), before saying the UI
   is done; a defect seen is fixed with its test. It records the
   durations in `build/qa-durations.tsv` of the main checkout and warns
   when a test exceeds 45 s or `--all` grows by 20 %: move a check down
   to a unit test, merge flows, cut fixed waits.
2. A flow no UI test covers: write the UI test (one class per flow,
   `CLAUDE.md`, *Tests*). When the expected behaviour itself is unknown,
   explore it first with argent (below), then freeze in the UI test only
   what must not regress: each wrong guess in an XCUITest costs a full
   run, argent answers in seconds.
3. By hand, only what the fake Mac cannot see, on the real iPhone after
   `$PWD/bin/run-ios-device`: show the user 3 to 5 boxes of `QA.md` at
   most, those of the areas the diff touches, never the whole list.
   `QA.md` only keeps what needs the real iPhone and the real Mac; a box
   a test can cover leaves it.

### Driving the simulator with argent

argent (`@swmansion/argent`) through its CLI, installed outside the
repository:

```sh
npm install --prefix "$HOME/.local/share/argent" @swmansion/argent
A="$HOME/.local/share/argent/node_modules/.bin/argent"
"$A" telemetry disable
U="$($PWD/bin/ios-simulator)"
.claude/skills/verify-heraldr/scripts/screen
"$A" run gesture-tap --udid "$U" --x 0.734 --y 0.541
"$A" run keyboard --udid "$U" --text "Fix issue 42"
xcrun simctl io "$U" screenshot ~/share/screenshots/<worktree>/verify-<screen>.png
```

`scripts/screen` wraps `native-describe-screen`: one line per element,
identifier, normalized tap point (what `gesture-tap` takes), traits,
label and value. About 20 lines for Home where the raw JSON is 600.

What the trial on Heraldr established (argent 0.30.1, iOS 26.2,
SwiftUI):

- `native-describe-screen` sees every `accessibilityIdentifier` of
  Home and compose, selection included (`[button,selected]` on the
  chosen tile), and the field value (`compose.text value='...'`).
- With a sheet open, it also lists the screen beneath, first, with
  shifted coordinates: read the ids of the sheet (`compose.*`), never
  tap an element of the screen beneath.
- `keyboard` typed digits and punctuation correctly on this worktree's
  simulator (fresh, en-US): the AZERTY digits seen on Morris did not
  show here. Heraldr has no login, so nothing to type for the starting
  state anyway.
- Taps by normalized point are reliable; there is no tap by id, so read
  `screen` again after each change of screen.
- `gesture-tap` answers `"tapped": true` even when a system alert
  swallows the tap. The `question` preset asks for the notification
  permission on the first launch on a simulator: the alert is
  SpringBoard's, absent from `screen`. When a tap changes nothing, run
  `"$A" run describe --udid "$U"` (ax-service, sees system alerts) and
  tap "Allow" (about `0.698,0.600` on the iPhone SE).
  `settings-permissions` cannot grant notifications on iOS.
- The question banner shows 12 s after launch: take the screenshot
  then, `screen` does not list it.
- The `notice` after a send lasts about 2 s: read `screen` right after
  the tap; a screenshot taken a few seconds later misses it.
- One tool-server serves every agent using this argent install (Morris
  sessions included): never `argent server stop`.

## Evidence

- `bin/qa`: `~/share/screenshots/<worktree>/<screen>-light.png` and
  `-dark.png`, result bundle in `build/qa/qa.xcresult`
- argent: screenshots taken with `xcrun simctl io <udid> screenshot`
  into `~/share/screenshots/<worktree>/verify-<screen>.png`, full
  resolution, no image in the context until read
- attach them to the PR with the `gh-image` skill

Cleanup never deletes them.

## Cleanup

At the end of a verification, stop only what this run started, by udid:

```sh
U="$($PWD/bin/ios-simulator)"
"$HOME/.local/share/argent/node_modules/.bin/argent" run stop-all-simulator-servers --devices "$U"
xcrun simctl shutdown "$U"
```

Never `argent server stop`, `killall Simulator` or a `pkill` by name.
Once the PR is merged, `bin/remove-worktree <name>`, run from the main
checkout by `/cleanup`, deletes the simulator with the worktree.
