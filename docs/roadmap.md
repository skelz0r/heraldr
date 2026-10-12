# Roadmap

## V1: MVP

See [spec.md](spec.md).

## V2: be told when a workspace needs me

Goal: know without looking that an agent is waiting, and know which one
and why.

Shipped, in a narrower form:

- push notification when a `<slug>-main` agent switches to `blocked`
  (AskUserQuestion question or permission request), and only those:
  worktree Claudes started by `/start` are ignored
- content: workspace label, agent name, question text
- tap on the notification: opens the agent's Remote Control session
  directly in the Claude app, otherwise Heraldr on the workspace with
  an "Open in Claude" button
- APNs delivery straight from the Mac through a herdr plugin, with no
  relay or daemon (see [architecture](architecture.md), Notifications)

Set aside for now:

- task completion notification (`done`)
- tabs (worktrees) and agents other than `-main`
- counter badge on the workspace row and on the icon
- Heeler-style Cloudflare Worker relay, AES-256-GCM encrypted payload
  and Notification Service Extension: the payload goes through APNs in
  clear (label, agent name, question text)

Open question: answer questions directly from the notification or the
app (reading the agent's screen then `send-keys`), or keep sending the
user to Claude mobile.

## V3: see where each agent stands

- workspace detail screen: one dot per agent (main Claude, shell,
  worktree agents), grouped by tab
- tab label = worktree name, last status, since when
- live stream through `events.subscribe` over streamlocal rather than
  polling
- maybe a Live Activity for a dispatch in progress

## Unprioritized ideas

- move to Xcode 26.6 (or 27): Heeler's, which would remove the
  `SessionDriver.swift` patch; in a dedicated branch, with
  `bin/local-ci` and `bin/qa --all`
- multiple machines (several QR codes)
- widget and Action button action to start voice directly
- Siri shortcut "dispatch to acme"
- dictation log analysis script (`mac/dictation-report.mjs`): share of
  edited words per week, undone replacements per misheard → term pair,
  hints followed, following the recipe in `docs/architecture.md`; to
  write after a few weeks of real dictations in
  `~/.config/heraldr/journal-dictees.jsonl`
