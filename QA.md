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
  Tailscale. Tailscale off too: amber dot, list kept; once the network
  is back, "Refresh" turns it green again.
- [ ] "Forget this Mac", then pair by scanning the QR code from
  `heeler.pair`: back on the main screen, Home as target.
- [ ] Install over the previous version: the app opens paired, history
  and lexicon are kept.

## Dictation (Voice/, UI/ComposeView.swift)

- [ ] iPhone in French, Settings > Dictation > Language on "Same as
  iPhone" (subtitle "French (France)"): a dictation in French is
  transcribed in French; switched to "English (United States)", the
  next dictation is transcribed in English.
- [ ] Dictate a request with hesitations: "Dictation cleaned up",
  "See original" shows the raw transcript.
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
- [ ] Settings > Action Button > Shortcut > Heraldr > "Dictate to
  Home", then press the button with the app killed, then in the
  background on another target: the microphone opens on Home's
  `main` each time, the request sent lands in Home.

## Notifications (Push/, HeraldrNotificationService/, mac/notify-hook.mjs)

- [ ] Get a `-main` to ask an AskUserQuestion: the notification
  arrives with label, session topic and question; the tap opens the
  session in the Claude app.
- [ ] iPhone locked, long press a question notification: one button
  per option; after Face ID, the option chosen is typed on the Mac and
  Claude resumes.
- [ ] AskUserQuestion with two questions, the first with previews:
  answer both from the notifications, then "Submit answers"; Claude
  receives both answers.
- [ ] Answer a question on the Mac, then tap an option in its older
  notification: "Answer not sent" notification, nothing typed.
- [ ] Send a simple question to a project: "Answer" notification with
  the summary, the tap opens the sheet with the full answer.
