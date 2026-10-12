# Vision

The [README](../README.md) says what Heraldr does and which conventions
it imposes. This is the why.

## Problem

An idea for a task shows up away from the keyboard: in the street, on
the couch, while testing a feature on the Mac. Turning it into agent
work means opening a terminal, finding the right herdr workspace, the
right Claude, running `/clear`, typing the prompt, then remembering
`/start`. Enough friction for the idea to get lost, or for the QA
remark to stay in the back of my head instead of reaching the Claude it
concerns.

## Everyday companion

Heraldr is used every day, between sessions at the Mac or in the middle
of QA: an idea or a remark comes up, it goes straight to the Claude
that should handle it. The app shows no code, the work is done and
reviewed on the Mac. It sends, and it tells me when a `main` is waiting
for an answer.

Voice first, because it costs the least when walking or with hands on
the Mac in the middle of QA. Write and Paste exist, but the voice
button dominates the screen.

## Why opinionated

Like an opinionated framework, Heraldr has nothing to configure: it
assumes a single way of organizing herdr, and that is why one gesture
is enough. Each convention has its reason:

- one agent per project with a predictable name (`<slug>-main`, tab 1):
  the app knows who to talk to without asking, and creates it if
  missing
- a `/clear` before each request: the `main` always starts from a fresh
  context, one idea does not pollute the next
- the `main` explores and asks its questions, but does not code: it
  ends with `/start`, which isolates each feature in its own worktree
  and tab. Tab 1 stays free for the next idea
- Home as global dispatcher: by voice, you don't want to pick a project
  before speaking. Home is the default target and relays to the right
  `main`
- toward a worktree tab, the opposite: no instructions and no `/clear`
  by default, because that is where you iterate on a feature already
  started and the Claude must keep its context

In return, Heraldr is useless to anyone who organizes herdr
differently. That is intended: the app is made for a single user and
their Mac.

## Positioning next to Heeler

[Heeler](https://github.com/ZingerLittleBee/Heeler) is a
general-purpose iOS client for herdr: console for all agents, terminal
attach, composer, uploads, diffs, push. Heraldr does not replace it:

- Heeler is for inspecting and driving in depth, whatever the
  organization of the workspaces
- Heraldr is for starting and moving work forward in a few seconds, by
  voice, within an imposed organization

Both live on the same Mac and reuse the same herdr plugin for pairing:
each app enrolls its own SSH key.

## What stays outside the app

- answering a `main`'s questions: a notification warns, the answer is
  given in the Claude app (Remote Control) or on the Mac
- following worktree progress: herdr, Heeler or the Claude app;
  Heraldr only shows the status of the `main` agents and of the
  targeted tab
- being notified by a worktree Claude: only `main` agents notify

## Principles

- big, readable, usable one-handed while walking: generous tap
  targets, the voice button dominant
- Liquid Glass (iOS 26), few elements, no color that carries no
  information ([design](design.md))
- no silent destructive action: never a `/clear` on an agent that is
  working, never a silent fallback to another target
- no daemon on the Mac: SSH, herdr's API, a queue script and a
  notification hook, which the app installs itself

## Direction

Unshipped tracks, detailed in the [roadmap](roadmap.md): see where each
agent of a workspace stands, start voice without opening the app
(widget, Action button, Siri), answer questions without leaving
Heraldr.
