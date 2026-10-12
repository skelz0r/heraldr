# QA on the iPhone

What stays manual: what neither the tests (unit, `dispatch.sh`, hook,
UI tests on the fake Mac) nor `bin/qa` can see, because it needs the
real iPhone and the real Mac: real SSH (LAN, Tailscale), real herdr
and real Claude, dictation and Apple Intelligence, camera, APNs push,
link to the Claude app, screen lock.

Nobody goes through this whole list. After a `bin/run-ios-device`,
the agent shows the user 3 to 5 boxes at most, chosen among the areas
the diff touches (paths in parentheses), and never a box the tests
already cover. A defect found is first reproduced in a test (fake Mac,
`fake-herdr`) when possible, then fixed.

## End-to-end send (Dispatch/, mac/dispatch.sh, Mac/)

- [ ] Write a request to a project without a `-main`: the agent is
  born in tab 1, its session is named `<label>—main` in Claude mobile,
  it receives `/clear` then the instructions.
- [ ] Send Home a request aimed at an open project: Home relays it,
  and the project's `-main` runs `/start`.
- [ ] Attach two screenshots from the photo library and send: the
  `-main` reads the images by their path and describes them.

## Network (Mac/, Pairing/)

- [ ] Wi-Fi off, Tailscale on: the app reaches the Mac through
  Tailscale. Tailscale off too: orange dot, list kept; once the network
  is back, "Refresh" turns it green again.
- [ ] "Forget this Mac", then pair by scanning the QR code from
  `heeler.pair`: back on the main screen, Home as target.
- [ ] Install over the previous version: the app opens paired, history
  and lexicon are kept.

## Dictation (Voice/, UI/ComposeView.swift)

- [ ] Dictate a request with hesitations: "Dictation cleaned up",
  "Show original" shows the raw transcription.
- [ ] Dictate longer than auto-lock: the screen stays on, then locks
  after the usual delay once stopped.
- [ ] With Spotify playing, dictate then stop: the music pauses while
  listening and resumes by itself on stop, with no error in Spotify;
  same with "Cancel" and when locking the iPhone during dictation (on
  return, the preview shows what was dictated).
- [ ] Dictate "get push the branch", correct it to "git push" and
  send, then dictate it again: the preview proposes "git push";
  `tail -1 ~/.config/heraldr/journal-dictees.jsonl` on the Mac shows
  the replacement.
- [ ] Uninstall, reinstall, pair: "Lexicon restored from the Mac".

## Notifications (Push/, mac/notify-hook.mjs)

- [ ] Get a `-main` to ask an AskUserQuestion: the notification
  arrives with label, agent and question; the tap opens the session in
  the Claude app.
- [ ] Send a simple question to a project: "Answer" notification with
  the summary, the tap opens the sheet with the full answer.
