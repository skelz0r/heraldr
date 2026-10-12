# Architecture

## Overview

```text
iPhone ──SSH (LAN or Tailscale)──> Mac sshd
                                    ├─ direct-streamlocal → herdr.sock (JSON API)
                                    └─ exec → detached dispatch script (queue)
```

No daemon and no extra port on the Mac. Same approach as Heeler
(Heeler ADR 0011: libssh2 `direct-streamlocal`).

## Mac side

Prerequisites already in place:

- Remote Login (sshd) on, port 22
- Tailscale SSH off (`RunSSH: false`), required because Heeler pairing
  relies on an OpenSSH forced `command=`
- `heeler` plugin installed and enabled
- herdr 0.9.3

Nothing else to install for the MVP. Notifications (V2) add one
prerequisite:

- Node in herdr's PATH (already required by the Heeler plugin)
- the team's APNs `.p8` key, copied as Apple downloads it to
  `~/.config/heraldr/AuthKey_<KEYID>.p8` (mode 600): the key id comes
  from the file name. One APNs key covers every app of the team, so
  the key of another app of the same team works

The rest comes from the app: bundle id (`<bundle id>`), team, APNs
environment (sandbox in Debug, production otherwise) and the herdr
plugin itself.

## Pairing

Reuses the Heeler plugin's `HERDR-PAIR:1` format as is
(`plugin/README.md`, section "Pairing Code envelope (v1)", test vectors
in `plugin/test-vectors/pairing-code-v1.json`):

1. on the Mac: `herdr plugin action invoke heeler.pair`, popup with a QR
2. the QR holds `HERDR-PAIR:1:<base64url(JSON)>`: `addrs`, `port`,
   `user`, `fp` (SHA256 fingerprint of the host key, pinned), `seed`
   (bootstrap Ed25519 key, single use, 2 min), `exp`
3. the app generates its Ed25519 Device Key (private part in the
   Keychain), connects with the bootstrap key, writes its public key on
   stdin
4. response `HERDR-ENROLL:OK:<fp>`, the bootstrap key is removed
5. the app remembers the address that answered, and tries the others
   on failure (LAN then Tailscale)

Heeler's test vectors become tests of the app-side parser (a consumed
public contract).

## SSH on iOS

`HeelerSSH` package (libssh2 + OpenSSL, Apache-2.0). It lives in a
subfolder of the Heeler repository (`Packages/HeelerSSH`, 20 MB
xcframework binaries): SPM cannot reference it directly. Heeler is
added as a git submodule `Vendor/Heeler`, pinned to a commit, and
XcodeGen declares the local package
`Vendor/Heeler/Packages/HeelerSSH`. Used for:

- `direct-streamlocal` to `herdr.sock`: herdr API JSON requests
  (reads: `workspace.list`, `tab.list`, `agent.list`)
- `exec`: running the dispatch script

Socket path: `~/.config/herdr/herdr.sock` (to be confirmed through the
default herdr session).

Both go through the `MacTransport` protocol (`Mac/`): `run` (exec of a
command, app-owned `CommandResult` with exit code and outputs) and
`exchangeWithHerdr` (one JSON request on `herdr.sock`). `MacLink`, the
SSH actor that holds the connection and reconnects, is its only real
implementation; `Dispatcher` and `HerdrClient` only know the protocol,
and nothing outside `Mac/` and `Pairing/` imports HeelerSSH.
`AppModel` receives an `AppEnvironment`: UserDefaults (history, paired
Mac), the lexicon file, the transport factory for a paired Mac
(`MacLink` and the Keychain key for real), pairing, the notification
authorization request and opening a link. It is the seam for the
`AppModel` tests and for the QA fake Mac (see *Fake Mac*).

## Dispatch

The app embeds a versioned shell script (`mac/dispatch.sh`). Each send
runs two SSH execs:

1. `install`: the script is written on stdin to
   `~/.local/state/heraldr/dispatch.sh` (always the version of the
   installed app)
2. `enqueue <workspace_id> <label_base64>`: the script resolves the
   workspace's `-main` (below), the wrapped prompt arrives raw on stdin
   and becomes a job
   `~/.local/state/heraldr/jobs/<timestamp>-<sequence>-<random>/`, then
   the script starts its detached runner:
   `nohup /bin/sh dispatch.sh run <agent> </dev/null >/dev/null 2>&1 &`

A workspace's `-main` is the agent of that workspace whose name ends
with `-main` (`herdr agent list`, filtered on `workspace_id`): a
renamed workspace keeps its own, even when its name no longer matches
the label. With several `-main`, the one named `<slug>-main` wins;
without it, `enqueue` and `relay` refuse (exit code 2) rather than
pick one. With no `-main`, the job targets `<slug>-main`, which the
runner creates. The app applies the same rule to `agent.list` for the
target state, but no longer passes a name: the Mac decides, at send
time.

A job is a folder of text files: `workspace_id`, `agent`, `label`,
`clear`, `prompt`, `state` (`queued`, `sending`, `sent`, `failed`) and
`error`. `dispatch.sh status` lists them as tab-separated lines for the
app.

The detached runner survives the phone going to sleep (spike 7). It
sets its PATH (`/opt/homebrew/bin` is missing in an SSH exec), takes
the agent lock (atomic `mkdir`, pid inside to take over a dead lock)
and processes the agent's jobs in name order: the timestamp to the
second, then a 12-digit counter kept under a `sequence` lock (a
`mkdir` never stolen while it is less than a minute old, even with no
pid written), which breaks ties between two sends in the same second
(the pid it replaces compared as text, `10000` before `9999`, and
wrapped to zero after 99999):

1. resolves tab 1 of the workspace (`herdr tab list --workspace`,
   number 1)
2. looks up agent `<agent>` (`herdr agent get`)
3. if missing: `herdr pane split` of the first pane of tab 1, with
   that pane's cwd, then
   `herdr agent start <agent> --kind claude --pane <pane> --
   --dangerously-skip-permissions --remote-control "<label>—main"`
   (equivalent to `dclaude`, keeping herdr's readiness detection)
4. `herdr agent wait <agent> --until idle --until done`, no timeout:
   this is the queue, which waits as long as the agent is working or
   blocked
5. `herdr agent prompt <agent> "/clear"` without `--wait` (spike 1:
   `--wait` fails with `agent_prompt_stalled`), then waits for
   `agent_session.value` to change
6. `herdr agent prompt <agent> "<wrapped prompt>" --wait --until
   working --until blocked`: returns as soon as herdr sees Claude
   working, without waiting for the end. Without this wait, herdr
   still shows the agent `idle` while it detects the new turn, and the
   next job passed its `agent wait` and sent its `/clear` while Claude
   was starting the previous one. An `agent_prompt_stalled` (nothing
   seen in 5 s, as with `/clear`) counts as sent, the text is gone,
   but the runner still waits up to 30 s (`agent wait --until working
   --until blocked`) for herdr to see Claude working: a slow start is
   not wiped by the next `/clear`. A turn short enough to finish
   before being seen costs those 30 s to the next job
7. `state` becomes `sent`, or `failed` with the error; `sent` jobs are
   deleted after an hour, `failed` ones after a day

A second send to a busy agent does not start a second runner: the lock
is taken, its job waits for the running runner to process it. Sends
therefore go out in order, each preceded by its `/clear`.

`enqueue-pane <workspace_id> <pane_id> <clear|keep>` targets the
Claude of a worktree tab, which the app designates by its `pane_id`
(first Claude of the tab in `agent.list`): the prompt arrives on stdin
as the app prepared it (dictation warning, no instructions) and goes
out unchanged. The job keeps the `pane_id` in `agent`, and `clear` in
a file of the same name (missing from jobs of an older script:
`/clear` is sent). Queue, `idle`/`done` wait and ordering are those of
a named agent, since `herdr agent get|wait|prompt` accept a `pane_id`
as target; the lock replaces `:` with `@`, which never appears in
agent names. The runner never creates an agent for a pane: it fails if
the pane no longer hosts a Claude (`agent` other than `claude`), if it
is in another workspace or if its Claude has a herdr name (a `-main`
has its own queue, keyed by name: two locks for the same Claude would
let two sends through at once). It repeats these checks after
`agent wait`, right before sending, since the pane may change occupant
during the wait, then sends `/clear` only for `clear`.

`relay <workspace_id>` lets the Home agent forward a request to the
project it targets: the raw request arrives on stdin, the script reads
the label with `herdr workspace get`, resolves the `-main` like
`enqueue`, wraps the request in the standard instructions and creates
a job like `enqueue`. It refuses Home (workspace number 1) as target.
The slug, the `-main` rule and the standard instructions therefore
exist twice, in `AgentName.swift` / `PromptEnvelope.swift` and in
`dispatch.sh`, to be kept aligned. On the shell side, the slug goes
through `perl` (canonical decomposition with `Unicode::Normalize`,
shipped with macOS) then byte-wise `tr`, which strips everything
non-ASCII: same result as Swift's filter on Unicode scalars,
multi-code-point emojis included. The script is always installed on
the Mac at relay time, since the send to Home just installed it.

`attach <jpg|png>` receives a screenshot attached to a request: the
image arrives raw on stdin, is written to
`~/.local/state/heraldr/attachments/<timestamp>-<id>.<ext>` (through a
renamed `.tmp`) and the script answers with its absolute path. The app
runs one `attach` per image before the `enqueue`, then cites the paths
in the request: Claude Code reads an image by its path with Read,
there is neither SFTP nor attachment on the herdr side. Images are not
tied to the job: `prune_jobs` (called by `run` and `status`) deletes
those older than a week, enough for a send left in the queue or a
session started later by /start.

## Dictation lexicon backup

```text
iPhone (dictation-lexicon.json) ──exec dispatch.sh lexicon-put──> ~/.config/heraldr/lexique.json
                                <──exec dispatch.sh lexicon-get── (after pairing, empty lexicon)
```

`LexiconKeeper` (`Voice` module) holds the lexicon for the whole app:
`AppModel.lexicon` reads and modifies it, the preview and Settings go
through it. Each change is written to the local file and raises
`lexicon-backup-needed` (UserDefaults); `sync` writes the whole
lexicon to the Mac and only lowers the flag if nothing changed during
the write. `AppModel` runs `sync` 2 s after a change and after each
successful refresh, on the already open `MacLink`, through
`Dispatcher.lexiconMirror` (`install` then `lexicon-get` or
`lexicon-put`).

`pair` calls `paired()`: empty lexicon, `lexicon-restore-pending` is
raised and `sync` reads the Mac before any write; otherwise the next
`sync` overwrites the Mac. The flag survives a relaunch, so that a
failed read never lets a write overwrite the backup. `LexiconMirror`
(two closures) is the test seam, the tests simulate the Mac without
SSH.

## Dictation journal

```text
ComposeView.send ──record──> dictation-journal.jsonl (pending, iPhone)
                                 │ exec dispatch.sh journal-append
                                 v
                  ~/.config/heraldr/journal-dictees.jsonl (Mac, append only)
```

`TranscriptCleaner.clean` returns, with the burst, a `CleaningTrace`:
text after the first replacement, replacements made by
`DictationLexicon.replacements(in:)` before and after the model, hints
given and whether they were followed, judged on the model's answer
before the second replacement (the only moment it exists).
`DictatedText` keeps the bursts and their revisions; on a successful
send, `AppModel.recordDictation` turns them into a
`DictationJournalEntry` (nothing for Write or Paste) that
`DictationJournal` appends to its pending file, then uploads.
`upload` pushes all pending lines in a single `journal-append` and
only removes those sent, a line added during the upload staying for
the next one; it runs again on every successful refresh.
`DictationJournalMirror` (one closure) is the test seam. A cut after
the write on the Mac resends the entry: `dispatch.sh` ignores it
thanks to its `id`.

Reading the numbers: the journal is meant to be analyzed by a Claude
on the Mac, one line per send, ignoring versions above 1 and
deduplicating by `id` to be safe. For each burst, the comparison that
matters is `previewed` → `edited`, word by word like the learning
(case, accents and punctuation at word edges ignored):

- share of retouched words: words of `previewed` changed over its
  word count, per week; should go down if the lexicon helps
- undone replacement: a term of `replacements` found fewer times in
  `edited` than in `previewed`, or replaced by the heard form; to
  report per heard → term pair to spot false positives, notably
  two-word variants learned with a neighboring word
- followed hint: `applied` of `hints`; a hint followed then undone in
  `edited` is a model false positive
- the model output before the second replacement is not kept:
  comparing `proposed` with `replaced` shows the cleanup and the
  second replacement together

## Notifications

```text
herdr ──pane.agent_status_changed──> heraldr plugin (node notify-hook.mjs)
                                      └─ HTTP/2 + JWT ES256 → APNs → iPhone
```

Registration: on the first successful refresh of each launch, the app
(authorization granted) runs an SSH exec
`dispatch.sh register-push <token> <sandbox|production> <topic>
<team_id>`, with `mac/notify-hook.mjs` on stdin. The script:

1. writes the hook and a `herdr-plugin.toml` manifest to
   `~/.local/state/heraldr/plugin/` (always the app's version)
2. links it once with `herdr plugin link`, if it is not already in
   `herdr plugin list`
3. remembers the device in `~/.local/state/heraldr/push-device.json`
   (a single iPhone)

The hook, a short process per state change started by herdr:

1. does nothing if the received state does not change the pane marker
   (`~/.local/state/heraldr/notified/<pane>`): `blocked` already
   notified, or another state with no pending notification
2. 3 s debounce, then `herdr agent get <pane>`: the state must hold,
   otherwise a newer event takes over. A state other than `blocked`
   that holds clears the marker and rearms the pane
3. ignores any agent whose name does not end with `-main`
4. session URL: `~/.claude/sessions/*.json` whose `sessionId` is
   `agent_session.value`, `https://claude.ai/code/<bridgeSessionId>`
5. question: read from the screen (`herdr pane read <pane> --source
   recent-unwrapped`), in the box between the last `─` rule and the
   selected option `❯ 1.`. `│` lines: the AskUserQuestion text.
   Otherwise the permission request title (`Bash command`: description
   before the first `╌` rule) or the `Do you want to …` line (file
   edited, overwritten or created). Not the transcript: Claude Code
   only writes the pending `tool_use` there once answered, the last
   readable `tool_use` is the one of the tool already run before
6. ES256 JWT signed with the `.p8`, POST `/3/device/<token>` on
   `api.sandbox.push.apple.com` or `api.push.apple.com`,
   `apns-collapse-id` = agent name
7. 200: marker set. 410 or `BadDeviceToken`: the device is forgotten
   until the app's next launch. Errors go to stderr, readable with
   `herdr plugin log list --plugin heraldr`

Payload: `aps.alert` (title = workspace label, subtitle = agent, body
= question), `workspace_id`, `agent`, `session_url`. On tap, the app
targets the workspace, opens `session_url` with `universalLinksOnly`,
and shows an "Open in Claude" card if opening fails or the URL is
missing.

### Answers

```text
Claude -main ──dispatch.sh answer <job_id>──> jobs/<job_id>/answer
                └─ node plugin/notify-hook.mjs answer <job_id> → APNs → iPhone
iPhone ──SSH read-answer <job_id>──> full answer (tap or refresh)
```

`create_job` replaces `{{job_id}}` in the prompt with the job id: the
instructions thus give Claude the exact command to answer. The hook,
started in `answer` mode, reads `agent`, `workspace_id`, `label` and
the first line of `answer` in the job folder, and posts with
`apns-collapse-id` = job id; same dead-token handling. `status` adds
the `answered` column: the app fetches through `read-answer` any
answer to a send it follows and does not have yet, whether the
notification was missed or not. An answered `sent` job escapes the
one-hour purge and goes seven days after its answer.

## Fake Mac

In Debug only (`ios/Heraldr/Debug/`, under `#if DEBUG`), a double of
the SSH + Mac boundary replaces `MacLink`: `FakeMac`, an actor
conforming to `MacTransport`, plays a scenario described as data
(`FakeMacScenario`, Codable): workspaces, tabs, agents and their
states, `queued`/`sent`/`failed` jobs, answers, starting history and
lexicon, failures per command (`enqueue`, `attach`, `tab.list`…) or
unreachable Mac. It interprets the commands `Dispatcher` sends to
`dispatch.sh` (`status`, `enqueue`, `enqueue-pane`, `attach`,
`read-answer`, `lexicon-get|put`) and answers herdr requests in the
real shape, extra fields included. Its `enqueue` resolves the
workspace's `-main` with the same rule as the script, and like it
refuses several `-main` none of which is `<slug>-main`. A send goes
`sent` to a ready agent (which then becomes `working`), `queued` to a
busy or already queued agent, `failed` to an agent of another
workspace or a pane with no Claude, like `dispatch.sh`.

The app turns it on at launch with `-HeraldrFakeMac <preset>` (`demo`,
`unpaired`, `unreachable`, `empty`) or with the `HERALDR_FAKE_MAC`
variable carrying a whole JSON scenario (UI tests). In this mode,
`AppEnvironment.fake` uses a dedicated UserDefaults suite, cleared at
launch, a temporary lexicon file, does not request notification
authorization (a system alert that would block XCUITest) and opens no
link. `AppModel` tests build it directly and drive its state between
two refreshes (`update`, `setJob`, `hold`/`release` to freeze a call
in flight).

## iOS app

- Swift 6, SwiftUI, iOS 26 minimum (Liquid Glass, SpeechAnalyzer,
  Foundation Models)
- modules:
  - `Pairing`: QR scan (VisionKit DataScanner), `HERDR-PAIR:1` parsing,
    enrollment, Keychain
  - `HerdrClient`: JSON requests over streamlocal, Codable models
  - `Dispatch`: prompt envelope, slug, script exec, attached
    screenshots (downscaled and converted to JPEG on the iPhone, sent
    by `attach`), history of the last 20 sends (UserDefaults)
  - `Voice`: SpeechAnalyzer + Foundation Models cleanup, dictation
    lexicon of terms and variants (JSON file in Application Support,
    `DictationLexiconStore`); the vocabulary goes through
    `AnalysisContext.contextualStrings`, which only
    `DictationTranscriber` uses today, not `SpeechTranscriber`: it is
    still given to both. Safe variants are replaced by code around
    the cleanup (`DictationLexicon.replacingKnownVariants`), the model
    going through `CleaningModel`, injectable in tests
  - `Push`: authorization, APNs token, notification taps
  - `UI`: list, buttons, preview
- Foundation Models unavailable (Apple Intelligence off, model not
  ready): the raw transcript is kept and the preview says so
