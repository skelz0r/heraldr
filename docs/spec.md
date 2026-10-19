# Specification

What Heraldr does, screen by screen, and what it expects from the Mac.
It is normative: a gap between the spec and the code is resolved in
favour of the spec, in the branch that finds it; a bug that cannot be
fixed right away is described as it behaves. The how (SSH, runner,
hook) is in [architecture](architecture.md), the why in
[decisions](decisions.md).

The app is in English, whatever the iPhone's language: its texts, and
what the system formats for it (relative dates, VoiceOver labels of
symbols), the app being localized in English only. Dictation listens
in the iPhone's language, or in the one chosen in Settings (§4.5,
§5.1).

## 1. Assumed herdr conventions

Every herdr workspace follows the same layout:

- tab 1: one or more Claudes and a shell
- following tabs: one worktree each

Home is herdr's workspace number 1, whatever its label (`~`,
`Home`…).

## 2. Pairing

Shown as long as no Mac is paired.

- instruction: run `herdr plugin action invoke heeler.pair` on the
  Mac, then scan the QR code, "valid for two minutes"
- full-frame QR scanner; without a camera: "Camera unavailable: paste
  the code instead"
- "Paste the pairing code" button: reads the clipboard
- only a text starting with `HERDR-PAIR` triggers pairing; an already
  scanned code is only sent again after a failure
- during enrollment: "Enrolling the iPhone…" overlay

Refusals, shown under the scanner. The first two, and a code expired
before enrollment, never contact the Mac:

| Case | Text |
| --- | --- |
| not a valid `HERDR-PAIR:1` code | "Not a herdr pairing code (<reason>)" |
| code without a bootstrap key | "This code has no bootstrap key: run heeler.pair again on the Mac" |
| expired code (before or during enrollment) | "The code expired: run heeler.pair again on the Mac" |
| `HERDR-ENROLL:ERR:<reason>` | "The Mac refused the enrollment (<reason>)" |
| `HERDR-ENROLL:OK` with a fingerprint other than the iPhone's key | "Enrollment failed: the Mac enrolled another key (…)" |
| the iPhone's key does not open a session after enrollment | "The Mac does not accept the iPhone's key yet: …" |

The Mac's host key is pinned by the QR code's fingerprint: another key
is never accepted. The address that answered moves to the front, the
others stay as fallbacks (LAN then Tailscale).

## 3. Connecting to the Mac

- at launch, the target is always Home (its `main`)
- until the first list has arrived: "Connecting to the Mac…"
- Mac unreachable before the first list: "Mac unreachable", the
  detail, "Retry" button. Once a list has arrived, the app keeps the
  last list and the target, only the Mac pill turns amber. Messages:
  - different host key: "The Mac's key changed (…): pair again"
  - iPhone key refused: "The Mac refuses this iPhone's key: pair
    again"
  - Tailscale SSH answered: "Tailscale SSH answered instead of the
    Mac's sshd: turn it off (RunSSH: false)"
  - connection still lost after redialing: "Connection to the Mac
    lost"
  - command with no reply before its timeout: "The Mac did not answer
    in time"
- a connection found lost by a command (typically gone stale while the
  app was in the background) is dropped and redialed once, without
  showing anything: the command runs again on the new connection.
  Never for `enqueue` and `enqueue-pane`, which the Mac may already
  have received (a request sent twice): a send absorbs the stale
  connection on its `install`, which runs first. A timeout is not
  redialed, the command may have run on the Mac
- Mac pill at the top (`<user>@<address>`, dot: green online, blue
  connecting, amber unreachable), menu:
  - "Refresh"
  - "Forget this Mac", confirmed by "Forget and pair again"; the key
    stays authorized on the Mac until it is removed from
    `~/.ssh/authorized_keys`
- refresh: when coming back to the foreground, on pull-to-refresh,
  after each send, then every 5 s as long as a send is queued, a named
  agent is working or the Claude of the targeted tab (§4.2) is
  working; stopped in the background

## 4. Main screen

Layout: target at the top over
about 38% of the screen, workspace grid below scrolling under the
target, at the bottom a voice drop of about 92 pt between two round
Write and Paste buttons.

### 4.1 Target

"TARGET", then the label (same size for every workspace), below it,
smaller and secondary, `main`, or the tab name when a tab is targeted
(§4.2), then the state of its `-main` (§6.4) and what the next send
will do:

| State | Title | Next send |
| --- | --- | --- |
| no `-main` agent in this workspace | No agent yet | A send will start Claude in tab 1, named `<slug>-main`. |
| several `-main` agents, none named `<slug>-main`, even with a queued send | Several -main Claudes | A send will fail: keep only one of <names>, or name it `<slug>-main`. |
| send queued or in progress to this agent | Sending… | A new send will go out right after. |
| `idle` or `done` | Ready | A send clears its context, then hands over the request. |
| `working`, send from the app to this target accepted by the Mac less than an hour ago (history, kept across relaunches) | Working on your request | A new send will wait until it finishes its work. |
| `working` | Working | A new send will wait until it finishes its work. |
| `blocked` | Asking you a question: answer in Claude mobile | A new send will wait until you have answered it. |
| state unknown to herdr | Unknown state | A new send will wait until it is ready. |

A `-main` of another workspace does not count, even named
`<slug>-main`. A send to a tab of the workspace does not occupy its
`-main`.

Tab target: the state is that of the tab's first Claude (order of
`agent.list`), same rows except:

| State | Title | Next send |
| --- | --- | --- |
| no Claude left in the tab | No Claude left in this tab | A send will fail: restart Claude in this tab on the Mac. |
| `idle` or `done` | Ready | A send hands over the request as is, keeping its context. (with "Send /clear first" checked in the preview: A send clears its context, then hands over the request.) |

The name `<slug>-main` is only shown while the agent does not exist,
and the names of the `-main` agents only when there are several:
elsewhere, the app says "Claude". Same rule for the preview's state
line (§5) and the notices after a send (§6).

### 4.2 Grid

- Home first, full width, then the others in two columns in herdr
  order (`number`)
- per workspace: label, dot of its `-main`'s state, the same source as
  the target (§4.1); the workspace's other tabs do not count:
  - grey ring: unknown state, no `-main` or several
  - green dot: idle or done
  - animated blue: working, or send queued or in progress
  - amber with halo: blocked
- "waiting" badge when a send to this workspace is queued or in
  progress, to its `main` or one of its tabs
- tap: the workspace's `main` becomes the target (lighter glass, bold
  name, no colour), even if one of its tabs was targeted. This is the
  only meaning of "focus": nothing moves on the Mac
- long press: "Target a tab of <label>" menu, with "main" then the
  workspace's tabs other than tab 1 that hold at least one Claude
  without a herdr name, in herdr order (`number`), named by their
  herdr label ("tab <n>" without a label); without such a tab: "No
  Claude in the other tabs". Choosing a tab makes it the target; the
  target tile shows its name under the label, its dot stays that of
  the `-main`
- the targeted tab is not persisted: it stays targeted until the next
  tap, a relaunch (back to Home) or the tab disappearing from herdr
  (back to the workspace's `main`)

### 4.3 Buttons

Write, voice (drop), Paste, disabled without a target. Write and Paste
only show their icon, labelled for VoiceOver. Paste takes the text and
images from the clipboard (three at most, as in the preview, §5.2).
Clipboard with no text nor image: failure notice "Clipboard empty",
"First copy the text or screenshot to send."

### 4.4 History

Round button to the right of the Mac pill, "Send history" for
VoiceOver. It opens a "History" sheet, with no Close button (swipe it
down), with two segments at the top, "Tasks" (open by default) and
"Questions".

"Tasks" lists the kept sends (§6) without an answer, most recent
first. A question stays there until its answer has arrived: the app
only knows a request was a simple question when it receives the
answer (§6.5).

- workspace label (`<label> — <tab>` for a send to a tab), relative
  date, status: a lone 10 pt dot in the state's colour, with no text,
  background or icon; solid yellow pulsing while sending, hollow
  yellow when queued, green once sent, red on failure. Colours specific
  to the history, distinct from those of agent states. VoiceOver reads
  the state (Sending…, Queued, Sent, Failed)
- the text, on four lines at most; "1 screenshot attached" or "<n>
  screenshots attached" in secondary below when the send had some; the
  reason under a failed send, in the red of "Failed"
- two icon-only actions, grey and without background, in the entry's
  header just before the dot; VoiceOver reads their name
- "Copy" puts the text in the clipboard, without the screenshots, then
  shows "Copied" for two seconds: the icon becomes a checkmark in the
  accent colour
- "Resend" closes the sheet and sends the text again as is to the
  original workspace, or to the original tab with the same `/clear`
  choice, with the paths of the screenshots already on the Mac
  (without sending them again: after a week, the Mac has deleted them
  and Claude will no longer find them), without going through the
  preview: it is a new send (§6), with its notice and its own entry.
  Failures, as a notice:
  - original workspace or tab missing from herdr: "<label> no longer
    exists" (`<label> — <tab>` for a tab), "Copy the text from the
    history to send it elsewhere."
  - workspaces not loaded yet: "Mac unreachable", "Resend the request
    once the workspaces have loaded."
  - send refused: "Failed to send to <label>" and the reason
- swiping an entry deletes it ("Delete")
- with no send: "No sends", "The last 20 sends will show up here."

"Questions" lists the sends that received an answer, most recent
first:

- workspace label, relative date of the answer
- the question, in secondary on two lines at most, then the answer's
  summary on three lines at most
- tap: the full answer (§6.5) in the same sheet, back with the arrow,
  "Copy" at the top right
- swiping an entry deletes it ("Delete")
- with no answer: "No questions", "Answers to the last 20 questions
  will show up here."

### 4.5 Settings

Round gear button to the right of the History button, "Settings" for
VoiceOver. It opens a "Settings" sheet, with no Close button (swipe it
down), half height and expandable, in two sections.

"Dictation": "Language", then "Lexicon".

"Language" shows "Same as iPhone" or the chosen language, and opens
"Dictation language":

- "Same as iPhone", with below it the name of the iPhone's first
  preferred language (Settings > General > Language & Region), not the
  app's language, which is always English; it is the default
- footer: "Only the microphone listens in this language: the app stays
  in English. Applies from the next dictation."
- "Languages": every language the iPhone can transcribe on device
  (SpeechAnalyzer's `SpeechTranscriber` and `DictationTranscriber`
  locales), named in English with their region ("French (Canada)"),
  in alphabetical order
- a checkmark marks the current choice; tapping a row selects it,
  kept immediately and across launches; nothing else changes (the
  lexicon and the cleanup are shared by every language)
- a language no longer transcribable keeps its choice; the dictation
  then says so (§5.1)

"Lexicon", with the number of terms, opens the list of the dictation
lexicon (§5.2), "Dictation lexicon":

- one row per term, in neutral text colour (not the accent), in
  lexicon order, most recent first: the term, and below it its heard
  variants separated by commas; as footer, "Most recent first. A
  variant typed here, or one of several words, is replaced by its term
  in every dictation; a learned single-word variant is only hinted to
  the cleanup.", then the state of the backup on the Mac (§5.2):
  "Backed up on the Mac <relative date>.", "Not backed up on the Mac
  yet: it will be at the next connection." or, with a restore pending,
  "The lexicon backed up on the Mac will be restored at the next
  connection."
- swiping a row deletes the term and its variants ("Delete"); no
  "Clear all"
- tapping a row opens "Edit term", the "+" button ("Add a term") opens
  "New term": "Term" section (one field), "Heard variants" section
  (one "Heard" field per variant, plus an empty one, swipe to remove,
  "Add a variant"), with no autocorrection nor forced capitalization,
  "Cancel" (cross) and "Save" (checkmark)
- "Save" stays disabled as long as the term and each filled variant do
  not count 1 to 3 words, or two of them are equal ignoring case,
  accents and punctuation at word edges; empty fields are ignored,
  spaces and punctuation at word edges are stripped on save
- a saved term moves to the top; a variant that belonged to another
  term moves to this one; a term renamed like another existing term
  merges with it. A variant added or edited here, even only in case or
  accents, is "typed", a variant kept as is keeps its origin; a term
  that is new, renamed or saved without variants is "typed", otherwise
  it keeps its own
- changes are kept immediately and apply from the next dictation
- with no term: "No terms", "Fix a misheard word in a dictation
  preview: the term is added here when you send, with what was heard."
  and "Add a term"

"Installed build" tells which build is running:

- "Version": `CFBundleShortVersionString` (0.1.0, never incremented)
- "Commit": short SHA of the built commit, suffixed `-dirty` if the
  worktree had changes; "unknown" outside a git repository
- "Built": local date and time of the build; "unknown" if missing

Commit and date are written into the `.app`'s `Info.plist` at each
build (`HeraldrBuildCommit`, `HeraldrBuildDate` in ISO 8601 UTC),
whatever the path: `bin/` or Xcode.

## 5. Composing a request

The three buttons lead to the same preview, on the current target;
the Action button leads to the dictation on Home (§5.3).

### 5.1 Dictation

- "Preparing the microphone…", then "Go ahead, I'm listening.", then
  the live transcript (SpeechAnalyzer, on device, in the language of
  Settings (§4.5): by default the iPhone's first preferred language,
  never the app's English), level waveform and timer; a language the
  iPhone cannot transcribe: "Transcription in this language is not
  available on this iPhone"
- while the microphone is active, the screen does not lock by itself;
  auto-lock comes back as soon as it stops (stop, cancel, error,
  screen closed, app in the background), so not during cleanup; a
  manual lock or an app switch always cuts the dictation, which moves
  on to cleanup like "Stop dictation": on return, the preview shows
  what was dictated
- closing the screen during dictation cancels it
- the microphone interrupts music or sound from another app
  (Spotify…) instead of playing over it, and hands it back as soon as
  it stops (stop, cancel, error, background, screen closed), before
  the transcript is finished: the app tells the system so that the
  other app resumes by itself, if it supports it
- "Cancel" closes without keeping anything; from a burst started from
  the preview (§5.2), it goes back to the preview with its text
  intact; "Stop dictation" moves on to cleanup
- nothing heard: "Nothing was heard.", the dictation screen stays
- cleanup by Foundation Models ("Cleaning up…", "Foundation Models, on
  device"): removes hesitations, repetitions and false starts without
  changing the meaning or adding content, keeping the transcript's
  language
- the raw transcript is kept when the model is unavailable ("Apple
  Intelligence is turned off", "the Apple Intelligence model is not
  ready yet", "this device does not support Apple Intelligence"), the
  dictation is too long, or the result is 40% or less, or 130% or
  more, of the raw length ("cleanup discarded: it strayed too far from
  the dictation")
- the lexicon (§5.2) serves the next dictation:
  - the 100 most recent terms are given to the transcription as
    contextual vocabulary
  - replacement by the code, before cleanup then on its result, and
    also when the raw transcript is kept: each typed variant, each
    variant of two words or more, and the term itself if it is typed
    or has two words or more, becomes the term, written with its case.
    Whole words only (separated by spaces, punctuation at word edges
    does not count), ignoring case and accents; the words of a variant
    are only separated by spaces; the longest variant goes first and a
    word already replaced is not replaced twice
  - a learned single-word variant is never replaced: when it appears
    in the transcript, it is hinted to the cleanup instruction
    (`"<heard>" may mean "<term>"`, to replace only if the sentence
    makes no sense otherwise), 3 at most, the most often fixed then
    the most recent; with no variant present, the instruction is
    unchanged
  - "See original" shows the transcript before any replacement, and
    also appears for a raw transcript that the replacement changed
- cleanup only applies to the burst just dictated, never to the text
  already in the preview

### 5.2 Preview

- at the top "Preview" and "Close"
- the target ("→ `<label> — main`" or "→ `<label> — <tab>`"), with its
  dot, changeable through "Change target": one section per workspace,
  its `main` (dot as in the grid, "waiting" badge) then, indented, its
  targetable tabs (§4.2) with the dot and badge of their Claude
- the target's state and the next send (§4.1)
- tab target only: "Send /clear first" checkbox, unchecked on opening
  and at each tab change
- targeted tab gone from herdr during the preview: "This tab no longer
  exists: pick another target.", "Send" disabled; never a silent
  fallback to the `main`
- the text, editable, placeholder "What should the agent do?";
  keyboard open for Write, prefilled for Paste and dictation
- the origin: "Written", "Pasted", "Dictation cleaned up", or "Raw
  transcript: <reason>"; once a burst has been dictated, the origin is
  dictation, even if the text comes from Write or Paste; "Raw
  transcript" wins if a burst was not cleaned up, with the reason of
  the last one; "See original" as soon as a burst has been cleaned up,
  it shows the raw transcript of each burst, separated by a line
- attached screenshots, under the text in the same frame: thumbnails
  in the image's aspect ratio, with rounded corners, in the order
  added, each with a "Remove screenshot <n>" cross; nothing when there
  are none
- "Attach screenshots", an icon-only button between the origin and
  "Dictate more", opens the system photo picker (images only, without
  asking for photo library access); three screenshots at most per
  request, the button is disabled once three are attached. Each image
  is scaled down to 1568 px on its longest side and converted to JPEG;
  meanwhile, a placeholder thumbnail holds its place in the selection
  order and "Send" is disabled, so that no screenshot is missing from
  the send. Its cross removes it, the only way out when an iCloud
  photo does not download; the other screenshots do not wait for it.
  Unreadable image: "An image could not be read." above "Send"
- "Dictate" (empty text) or "Dictate more" opens the dictation screen
  (§5.1), whatever the origin; the cleaned-up burst is appended at the
  end of the text, after a line break, without touching the text
  already there, fixed or not
- "Send", disabled while the text is empty or during the send, even
  with screenshots: an image alone does not say what to do with it; to
  a tab with no Claude, the send fails before the Mac: "No Claude left
  in <label> — <tab>: restart it on the Mac."; on failure, the error
  shows above and the preview stays open; on success it closes
- learning from corrections, without displaying anything: when Send is
  tapped on a dictation, the proposed text (cleaned up, or raw) is
  compared word by word with the sent text, ignoring case, accents and
  punctuation at word edges. With several bursts, each proposed text
  is compared with what it had become just before the next burst, the
  last one with the sent text; the text already there before a burst
  is part of the proposed text. Each replacement of 1 to 3 words by 1
  to 3 words is kept ("heard → meant"); a replacement of a single word
  by a single word keeps the next (or previous) unchanged word, "on
  push → git push" rather than "on → git". Nothing is kept when more
  than half of the proposed words changed (rewrite), nor for an
  addition or deletion alone, nor for a written or pasted send
- each kept replacement stores the heard text as a "learned" variant
  of the meant term, created if missing (matched ignoring case and
  accents, it keeps its original spelling); a heard text belongs to
  one term only: already known, it moves to the last meant term and
  goes back to the top, with its counter increased if it keeps the
  same term. Putting a variant back in the preview in place of its
  term ("Acme" → "ack me") removes that variant from the term instead
  of learning the reverse, including when the neighbouring word was
  kept ("GitHub tomorrow" → "guithub tomorrow"). A learned term with
  no variant left disappears; beyond 200 terms, the least recent are
  forgotten. The lexicon can be viewed and fixed in Settings (§4.5)
- the lexicon is kept on the iPhone, in a versioned JSON file
  (`dictation-lexicon.json`, Application Support):

  ```json
  {
    "terms" : [
      {
        "source" : "typed",
        "text" : "Acme",
        "updatedAt" : "2026-10-12T09:00:00Z",
        "variants" : [
          { "count" : 2, "heard" : "ack me", "source" : "learned", "updatedAt" : "2026-10-12T09:00:00Z" }
        ]
      }
    ],
    "version" : 1
  }
  ```

  `source` is `typed` or `learned`, an unknown value is read as
  `learned`; any other field is ignored; a file of a higher version is
  not read. Corrections from the old lexicon (UserDefaults) are taken
  over once: each meant text becomes a learned term, each heard text
  one of its learned variants
- backup on the Mac (`lexicon-put`, §8.2), without dictation ever
  reading the Mac: after each change (2 s after the last one) and at
  each successful refresh (§3), as long as the last change is not
  backed up, the whole lexicon is written, in the background. A
  failure is not shown: it is retried at the next refresh, and the
  list (§4.5) says the backup is pending. The Mac's backup is
  overwritten, never merged: a change made on the Mac is lost
- restore, only right after a pairing (§2) with an empty lexicon on
  the iPhone, typically after a reinstall: the app reads the backup
  (`lexicon-get`) before any write, takes it as is (a term learned on
  the iPhone in the meantime wins over the Mac's) and announces it:
  "Lexicon restored from the Mac", "<n> terms recovered from the
  backup." (or "1 term recovered from the backup."). As long as the
  read fails, nothing is written on the Mac and it is retried at each
  refresh, even after a relaunch. Missing, empty or unreadable backup:
  nothing is taken over. Pairing with a non-empty lexicon: the backup
  is not read, it is overwritten
- dictation journal, to measure the lexicon in real use, without
  displaying anything: each successful send of a dictation (not of a
  written or pasted text) adds an entry to the iPhone's journal
  (`dictation-journal.jsonl`, Application Support), one JSON line per
  send:

  ```json
  {"id":"5B1F…","salves":[{"edited":"Run Acme and the GitHub.","hints":[{"applied":true,"heard":"guithub","term":"git hub"}],"previewed":"Run Acme and the git hub.","proposed":"Run Acme and the git hub.","raw":"run ack me and the guithub","replaced":"run Acme and the guithub","replacements":[{"heard":"ack me","term":"Acme"}]}],"sent":"Run Acme and the GitHub.","sentAt":"2026-10-12T09:00:00Z","version":1}
  ```

  - one salve per dictation burst, in order: `raw` the raw transcript,
    `replaced` after the code's replacement before cleanup,
    `replacements` each replacement made by the code before and after
    cleanup (the heard text as written, the term), `hints` the
    variants hinted to the cleanup, `applied` true when the model's
    output no longer has the heard text and contains the term (false
    without cleanup), `proposed` the burst's text, `reason` the reason
    for a kept raw transcript (absent if cleaned up), `previewed` the
    whole preview text right after the burst and `edited` what it had
    become before the next burst, or at send for the last one (the
    texts compared by learning)
  - `sent` the sent text, `sentAt` the time of the send, `id` unique
  - a line of a higher version, or an unknown field, is to be ignored
    by whoever reads the journal
  - pending entries go to the Mac (`journal-append`, §8.2) right after
    the send and at each successful refresh (§3), in the background;
    they only leave the iPhone once received. A failure is not shown,
    it is retried at the next refresh, even after a relaunch. Beyond
    500 pending entries, the oldest are forgotten
  - the journal never leaves the iPhone and the paired Mac: the
    pending file is excluded from the iCloud backup
  - the entry keeps the text as it was when Send was tapped, even if
    it is edited during the send

### 5.3 Action button

- the app exposes one App Shortcut, "Dictate to Home" (Siri phrases
  "Dictate to Home with Heraldr", "Dictate with Heraldr"), to pick in
  Settings > Action Button > Shortcut; also available in Shortcuts and
  Siri
- it opens the app and the dictation screen (§5.1) on Home's `main`,
  whatever the target was, the same way a tap on the voice drop does;
  Home also becomes the target of the main screen
- works the same with the app killed, in the background or open:
  the microphone starts without waiting for the workspace list; until
  it arrives, the target reads "Home — main", then Home's label
- the History, Settings or answer sheet, or the "Forget this Mac?"
  confirmation, open at that time is closed first
- a preview already open keeps its text and its target: the button
  starts a "Dictate more" burst there (§5.2); a dictation or a cleanup
  in progress, or a send, is left as is
- app not paired: the pairing screen, no dictation
- microphone or speech recognition refused: same message as from the
  voice drop (§5.1)

## 6. What a send does

Target: the workspace's `-main` (§6.4), resolved by the Mac at send
time. A send to a tab follows §6.3.

1. agent missing: split of a pane of tab 1 (cwd of that pane) and
   Claude started in yolo mode, named `<slug>-main`, Remote Control
   name `<label>—main` (`~` becomes `home`)
2. agent `idle` or `done`: `/clear`, then the wrapped prompt
3. agent `working` or `blocked`: the send waits on the Mac and goes
   out as soon as it is `idle` or `done` again
4. several sends to the same agent go out in order, each preceded by
   its `/clear`; the next one waits for Claude to have started then
   finished the previous one
5. an agent with the same name in another workspace is never targeted:
   the send fails
6. several `-main` agents with none named `<slug>-main`: the send is
   refused, nothing is queued or started

Notice after the send (5 s, closed on tap; a notice replacing another
one stays 5 s in turn):

| Agent at send time | Notice |
| --- | --- |
| missing | Sent to <label> — The Mac starts Claude in tab 1, named <agent>, then hands it the request. |
| `idle` or `done` | Sent to <label> — The Mac clears Claude's context, then hands it the request. |
| other, or send already queued | Queued for <label> — Claude is busy: the request goes out as soon as it is done. |

To a tab, `<label>` becomes `<label> — <tab>`, and an `idle` or `done`
Claude without "Send /clear first" gives "Sent to <label> — <tab> —
The Mac hands the request as is to Claude, which keeps its context."

A send tracked by the app that turns `failed` shows "Failed to send to
<label>" (`<label> — <tab>` for a tab) with its reason, only once.
Tracked: kept in the history without already being failed (even if it
fails before the refresh following the send, or while the app was
closed), or seen on the Mac at the previous refresh (a relay from
Home). Several failures found at the same refresh give a single
notice, "<n> sends failed", with one "<label>: <reason>" line per
send.

With screenshots, the app first puts them on the Mac (`attach`, §8.2),
one by one, then creates the job; the request cites them by their path
after the text:

```text
<text>

Attached screenshots, read them with Read:
- <path on the Mac>
```

This block is part of `<text>` in the instructions (§6.1 to §6.3). A
screenshot refused by the Mac makes the send fail before the job is
created; screenshots already put stay in the history and go out again
with "Resend".

Each send is recorded on the iPhone as soon as Send is tapped, before
connecting to the Mac: the text as typed (without the instructions),
the workspace, the tab and the `/clear` choice for a send to a tab,
the date, and the screenshots' paths once put on the Mac. Its status:

| Moment | Status |
| --- | --- |
| the Mac has not answered yet | Sending… |
| job created, `queued` or `sending` | Queued |
| job `sent` | Sent |
| failure before the Mac, or job `failed` | Failed, with the reason |
| still "Sending…" when the app launches (crash during the send) | Failed, "Send interrupted before the Mac replied." |

A job purged by the Mac leaves the send at its last status. Only the
20 most recent sends without an answer are kept, and separately the 20
most recent answered questions: an answer moves its send from the
former to the latter.

### 6.1 Standard instructions

```text
Request sent from the iPhone (may come from voice dictation: watch for
transcription errors).

<text>

Instructions:
- explore the code to understand the request, change nothing here
- if the request is ambiguous, ask your questions with AskUserQuestion
- if it is a simple question with no work to do: answer without
  /start using `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" answer
  <job_id>`, with on standard input a one-sentence summary, a blank
  line, then the full answer in markdown
- otherwise, you must finish by dispatching the work with /start
```

`<job_id>` is written `{{job_id}}` by the app and replaced by the job
id when `dispatch.sh` creates it (§8.2).

### 6.2 Send to Home

Home is the default target, so many requests land there while they
are meant for a project. Its `-main` (`home-main` when it creates it)
receives separate instructions:

```text
Request sent from the iPhone to Home, the app's default target (may
come from voice dictation: watch for transcription errors).

<text>

Instructions:
- change nothing here
- if it is a simple question with no work to do: answer it yourself,
  without relay or /start, exploring whatever you need (including the
  target project), then hand in your answer using
  `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" answer <job_id>`,
  with on standard input a one-sentence summary, a blank line, then
  the full answer in markdown
- otherwise, identify the target project among the open herdr
  workspaces: labels with `herdr workspace list`, folders with
  `herdr pane list --workspace <workspace_id>` (cwd)
- if several projects could match, ask with AskUserQuestion before any
  relay
- if a project is targeted, relay the request to it then stop, without
  /start: `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" relay
  <workspace_id>` with on standard input the original request, fixed
  for obvious transcription errors, completed with the answers to your
  questions and followed by the paths of the attached screenshots if
  any
- if no open project is concerned: explore whatever you need to
  understand the request, ask your questions with AskUserQuestion if
  it is ambiguous, and you must finish by dispatching the work with
  /start
```

The relay follows the same path as a send from the app to that
workspace (same `-main`, creation, queue, `/clear`, standard
instructions) and shows on the project's row. A relay to Home or to an
unknown workspace is refused.

### 6.3 Send to a tab

Target: the first Claude of the chosen tab (§4.2), designated by its
`pane_id`, without a herdr name (the Claudes started by /start have
none).

1. the text goes out preceded only by the dictation warning, without
   standard instructions (§6.1) nor Home instructions (§6.2), reserved
   for the `main`:

   ```text
   Request sent from the iPhone (may come from voice dictation: watch
   for transcription errors).

   <text>
   ```
2. `/clear` before the text only if "Send /clear first" is checked
3. Claude `working` or `blocked`: same queue as for the `main`, the
   send waits for `idle` or `done`, order kept
4. Claude is never started: a pane that no longer hosts a Claude,
   that belongs to another workspace or whose Claude has a herdr name
   (a moved `-main`, which has its own queue) makes the send fail;
   checked when the job is picked up and right before sending, after
   the wait

### 6.4 Naming

- a workspace's `-main`: the herdr agent of that workspace whose name
  ends with `-main`, whatever the rest of the name (a renamed
  workspace keeps its own); if there are several, the one named
  `<slug>-main`, otherwise none (§4.1, §6)
- name given to the `-main` the Mac creates: `<slug>-main`
  - slug: accents removed (canonical decomposition), then any
    character outside `[a-z0-9_- ]` after lowercasing removed (emojis
    included), spaces at the edges dropped and the others turned into
    `-`, `w-` in front if it does not start with a letter, truncated
    to 27 characters, `~` becomes `home`
  - examples: `home-main` (`~`, `🏠 Home`), `heraldr-main`
    (`📯 Heraldr`), `naive-search-main` (`Naïve search`),
    `acme_app-main`, `w-2025-roadmap-main`; vectors shared by the app
    and `dispatch.sh` in `mac/test/agent-names.tsv`
  - herdr constraint: `[a-z][a-z0-9_-]{0,31}`, unique among live
    agents
- Claude session (Remote Control, visible in Claude mobile):
  `<label>—main`, `~` becomes `home`

### 6.5 Answer to a simple question

The `-main` decides, from the instructions (§6.1, §6.2), that a
request is a simple question: the app offers no choice.

1. it explores without changing anything, without /start, and hands in
   its answer through `dispatch.sh answer <job_id>`: first line the
   summary, then the full answer in markdown
2. the Mac keeps the answer with the job and pushes a notification
   (§7)
3. the send moves to "Questions" (§4.4) as soon as the app fetches
   it: on tapping the notification, or at the refresh that sees the
   job answered in `status`, missed notification included
4. a relay from Home (§6.2) creates a job the app does not track: if
   the project's `-main` answers it anyway, the notification opens the
   answer, which the history does not keep
5. a send to a tab (§6.3) has no instructions, so no answer of this
   kind

Answer sheet, opened from the bottom, with no Close button (swipe it
down), half then full screen: title = the send's label, the question
in secondary, the summary as heading, then the full answer (markdown:
headings, lists, code blocks, bold, italics, inline code and links),
selectable. "Copy" copies the full answer. While it arrives from the
Mac, the notification's summary shows alone with a progress indicator;
Mac unreachable: "Full answer unavailable: <reason>" under the
summary. The sheet closes the history and settings if they are open.

## 7. Notifications

- permission asked at the first successful refresh, once per launch;
  granted, the app sends its token to the Mac (`register-push`) at
  each launch
- failure of that send: "Notifications not set up on the Mac" notice;
  APNs registration failure: "Notifications unavailable"
- a notification goes out when a `-main` agent turns `blocked` and
  stays so for 3 s, once per question; never for worktree Claudes.
  Title: workspace label, subtitle: topic of the session (terminal
  title of the Claude, none when it is empty or the default "Claude
  Code", never the agent name, always `<slug>-main`), body: what the
  agent's screen shows, truncated to 178 characters ("…"):
  - question of an AskUserQuestion, whatever its rendering (options
    with a preview, several questions in tabs, multiple choice): the
    question on screen; on the review step of several questions,
    "Submit your answers? <answer> · <answer>"
  - Bash permission: "Wants to run: <description>", or "Wants to run a
    command" without a description, never the raw command
  - file permission: "Wants to edit: <file>" (edit, overwrite) or
    "Wants to create: <file>"
  - other permission: "Permission request: <request title>"
  - nothing recognized: "Waiting for an answer"
- a notification goes out when a `-main` hands in its answer to a
  simple question (§6.5): title = the send's label, subtitle "Answer",
  body = summary, truncated to 178 characters ("…"); tap: the answer
  sheet, never the Claude app. Without a registered iPhone, the
  answer is kept without a notification
- notification received with the app open: banner, list and sound
- tap: the agent's workspace becomes the target, then the session
  opens in the Claude app. If the link is missing or the Claude app
  does not take it: "<agent> is waiting for an answer" card, "The
  session did not open in Claude.", "Open in Claude" button

## 8. Contract with the Mac

The app only talks to the Mac over SSH, and this contract changes on
both sides at once: the script is reinstalled by the app before each
`enqueue`, `register-push`, `lexicon-get`, `lexicon-put` and
`journal-append`, the hook with `register-push`. `status` reads the
already installed script, which may come from a previous version of
the app: its output stays readable by the newer app.

### 8.1 herdr API (`herdr.sock`)

- `workspace.list`: `workspace_id`, `number`, `label`; its
  `agent_status`, aggregated over all tabs, is not read
- `agent.list`: `name` (missing for a Claude started by hand or by
  /start), `agent` (`claude` for a Claude), `pane_id`,
  `workspace_id`, `tab_id`, `agent_status`
- `tab.list` without parameters: `tab_id`, `workspace_id`, `number`,
  `label`; its `agent_status` is not read. Failure of this call: the
  last received list is kept (no tab before the first one), the rest
  of the screen is unchanged
- tolerance: any other field is ignored, an unknown `agent_status`
  becomes "Unknown state"; an agent without `tab_id` or `workspace_id`
  is read (it counts for no workspace or tab), and an unreadable item
  of a list (expected field missing or of another type) is ignored
  without hiding the others

### 8.2 `dispatch.sh`

| Command | Standard input | Output |
| --- | --- | --- |
| `install` | the script | nothing |
| `enqueue <workspace_id> <label_base64>` | wrapped prompt | job id; code 2 with several `-main` agents and none `<slug>-main` (reason and names on stderr) |
| `enqueue-pane <workspace_id> <pane_id> <clear\|keep>` | raw text | job id; code 2 for a `pane_id` outside `[A-Za-z0-9]+:[A-Za-z0-9]+` or an unknown option |
| `relay <workspace_id>` | raw request, without its surrounding whitespace as in the app | job id; code 2 to Home, an unknown workspace, an empty request or several `-main` agents and none `<slug>-main` |
| `attach <jpg\|png>` | an image | absolute path of the file kept on the Mac; code 2 for an empty image, one over 20 MB, or another extension; code 1 without a path when the Mac cannot write it |
| `answer <job_id>` | summary on the first line, blank line, full answer | nothing; code 2 for an unknown job or an empty first line; notification refused: answer kept, reason on stderr, code 0 |
| `read-answer <job_id>` | nothing | the answer as handed in; code 2 without an answer |
| `status` | nothing | one line per job: `id`, `workspace_id`, `agent`, `state`, `error`, `answered` (empty without an answer), tab-separated |
| `register-push <token> <sandbox\|production> <topic> <team_id>` | the hook | nothing |
| `lexicon-get` | nothing | the lexicon backup as written, nothing without a backup (code 0) |
| `lexicon-put` | the lexicon (JSON of §5.2) | nothing; code 2 for an input without a readable integer `version`, previous backup intact |
| `journal-append` | dictation journal entries (§5.2), one JSON line each | nothing; code 2 for an empty entry, one that is not a JSON object, without an integer `version` or without an `id` in `[A-Za-z0-9-]{1,64}`, journal intact and nothing from the send appended; code 1 when the journal cannot be written or stays held by another append for more than 10 s |

- `enqueue` and `relay` resolve the workspace's `-main` (§6.4) through
  `herdr agent list`; without a `-main`, the job targets
  `<slug>-main`, created when processed
- `agent`: name of the resolved `-main`, or `pane_id` for a send to a
  tab (an older app counts it in the workspace); the app counts for
  the `-main` any job whose `agent` has no `:`
- `state`: `queued`, `sending`, `sent`, `failed`; the app ignores a
  line with an unknown state
- `error`: on one line, tabs and line breaks replaced by spaces
- `answered`: missing from an older script, the app then reads the job
  as unanswered
- `{{job_id}}` in the prompt of `enqueue` or `relay` becomes the job
  id
- `sent` jobs disappear after an hour, `failed` ones after a day,
  those with an answer seven days after it
- `attach` images live under `~/.local/state/heraldr/attachments/` and
  disappear after a week, independently of jobs: a send can wait in
  the queue, and the Claude receiving the request can hand it over
  through /start to another session that will read them later
- `register-push` refuses a token outside `[0-9a-f]{64,200}`, a team
  outside `[A-Z0-9]{10}`
- the lexicon is backed up in `~/.config/heraldr/lexique.json`,
  written to a temporary file then renamed; the script only reads its
  `version` and returns it byte for byte
- the dictation journal is appended to
  `~/.config/heraldr/journal-dictees.jsonl`, in the order received,
  line by line; an entry whose `id` is already in the journal is
  ignored, so that a send repeated after a disconnection does not
  duplicate it. Accepted entries are appended at the end, without
  rewriting what is there, one append at a time (lock), after a line
  break if the last line has none. It is neither read by the app nor
  purged: it is emptied by hand

### 8.3 Notification payload

Question: `aps.alert` (`title`, `subtitle`, `body`), `workspace_id`,
`agent` and optional `session_url`. Without `workspace_id` or `agent`,
the tap is ignored.

Answer: `aps.alert`, `kind` = `answer`, `job_id`, `workspace_id`,
`agent`. Without `kind` = `answer` or `job_id`, the notification is
read as a question.

## 9. Out of scope

- answering the agent's questions from the app
- task completion notification
- answer to a simple question sent to a tab
- per-agent detail
- multiple machines, named herdr sessions
