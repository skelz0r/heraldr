# Risks and things to check

To settle with a spike before writing the app. Results of the
2026-10-10 spike (herdr 0.9.3, Claude Code 2.1.296, macOS 26.4), on a
throwaway "Spike compagnon" workspace and its
`spike-compagnon-main` agent.

1. `/clear` and Remote Control: do the `<label>—main` name and the
   Remote Control connection survive a `/clear`? If not, rerun
   `/remote-control <name>` after each `/clear` in the dispatch script.
   - Settled: after `/clear`, the `/remote-control` box shows the same
     `claude.ai/code/session_…` URL as before. The connection survives,
     no need to rerun `/remote-control`.
   - New finding: `herdr agent prompt <agent> "/clear" --wait` fails
     with `agent_prompt_stalled`, because `/clear` never moves the
     agent to `working`. The script therefore sends `/clear` without
     `--wait`, then waits for `agent_session.value` (Claude session id)
     to change, which marks the end of the `/clear`.
   - Still to confirm on the phone: the name shown in Claude mobile
     after `/clear` (the terminal does not show the name).
2. Remote Control name: do the em dash and `~` go through
   `--remote-control` and the Claude mobile display?
   - CLI side: `--remote-control "Spike compagnon—main"` is accepted,
     herdr quotes it correctly in the pane. `~` is never passed as is
     (it becomes `home`). Mobile display to confirm.
3. `remoteControlAtStartup: true` in the settings: conflict or
   duplicate with `--remote-control <name>`?
   - A single Remote Control session in the terminal. No duplicate in
     Claude mobile, to confirm.
4. `herdr agent prompt` with multi-line text: check that bracketed
   paste keeps line breaks in Claude Code.
   - Settled: a 5-line prompt, one of them empty, with accents, em
     dash, quotes, apostrophe and `$HOME`, arrives intact. Claude counts
     5 lines and copies line 4 identically.
5. `HERDR-PAIR:1` format: coupled to a version of the Heeler plugin.
   Pin the tested version and run the test vectors in local CI.
   - Installed plugin: Heeler `f98028b` (v0.1.13, plugin 0.6.0). The
     submodule is pinned to that commit and the tests read the vectors
     from the submodule.
6. HeelerSSH: stable public API? Size of the OpenSSL binary. Plan B:
   Citadel if it supports streamlocal.
7. Detached process through `nohup` in SSH exec: check that it survives
   the channel closing on macOS (otherwise `setsid` or
   `launchctl submit`).
   - Settled: `nohup /bin/sh job.sh </dev/null >/dev/null 2>&1 &` in
     SSH exec returns in 1 s and the process is still alive 15 s after
     the channel closes, without receiving SIGHUP. Redirecting all
     three descriptors is required: otherwise sshd waits for them to
     close.
   - Later: macOS 26.4 `nohup` exits with "can't detach from console"
     when started from a terminal (herdr pane, agent shell), so the
     runner never started outside SSH and the `dispatch.sh` tests
     failed. The script ignores SIGHUP itself instead
     (`trap '' HUP` in a subshell), which needs no console.
   - New finding: in SSH exec the PATH does not contain
     `/opt/homebrew/bin`, hence no `herdr`. The script sets its PATH.
8. Foundation Models: cleanup quality in French, context limit for a
   long dictation.
9. Path of `herdr.sock` with several named herdr sessions.
   - Default session: `~/.config/herdr/herdr.sock`, confirmed (same
     JSON format as the CLI, one request per connection). Named
     sessions live in `~/.config/herdr/sessions/<name>/herdr.sock`, not
     handled in the MVP.
10. New: a folder Claude has never opened blocks startup on the "Do you
    trust this folder?" question. `agent start` then returns
    `agent_not_ready` and the agent is `blocked`. The script does not
    answer for the user: it waits for the agent to become `idle`, the
    question is handled on the Mac.

## Push notification spike

Spike of 2026-10-10 (herdr 0.9.3, Claude Code 2.1.296, Node 25),
before writing push notifications for questions from `-main` agents.

11. Remote Control session URL of an agent, available on the Mac?
    - Settled: `~/.claude/sessions/<pid>.json` holds the `sessionId` of
      the Claude session, the one herdr exposes in
      `agent_session.value`, and its `bridgeSessionId`
      (`session_01…`). The URL is
      `https://claude.ai/code/<bridgeSessionId>`, the one
      `/remote-control` shows.
    - `claude.ai/code/*` is a universal link of the Claude app
      (claude.ai's `apple-app-site-association`, appID
      `Q6L2SF6YDW.com.anthropic.claude`): Heraldr opens it with
      `universalLinksOnly`, and falls back to an "Open in Claude"
      button if the app does not take it.
    - The question text is not in the transcript
      `~/.claude/projects/<encoded cwd>/<sessionId>.jsonl` at the time
      of `blocked`: measured, an AskUserQuestion only appears there on
      the answer (24 s later), and the `tool_use` of a Bash or Write
      permission is not there during the request. Reading the last
      `tool_use` gave the previous tool, already run, hence
      "Permission request: Bash" notifications for simple questions.
      The pane screen (`herdr pane read`) shows the question or the
      permission request as soon as `blocked` happens.
12. Switch to `blocked` without a daemon?
    - Settled: a herdr plugin declares
      `[[events]] on = "pane.agent_status_changed"`; herdr starts a
      short process per status change with `HERDR_PLUGIN_EVENT_JSON`
      (`pane_id`, `workspace_id`, `agent_status`). The agent name is not
      there: it comes from `herdr agent get <pane>`, which also serves
      to check the status again after the debounce. `herdr plugin link`
      registers a local plugin without a build.
13. APNs HTTP/2 delivery from the Mac?
    - Settled: Node (already required by the Heeler plugin) signs the
      ES256 JWT with `node:crypto` (`dsaEncoding: "ieee-p1363"`) and
      posts with `node:http2`, with no dependency. The system's curl
      8.7.1 also has nghttp2, but signing ES256 in shell is painful.
    - The APNs `.p8` key of another app of the same team
      (`<apns key id>`, team `<team id>`) passes authentication for the
      `<bundle id>` topic: sandbox and production answer
      `BadDeviceToken` to a fake token, not `InvalidProviderToken`. An
      APNs key is valid for every app of the team.
    - Checked on the iPhone: an AskUserQuestion from `home-main`
      produces the notification (label, agent, question), and the tap
      opens the session in the Claude app.
    - `herdr plugin link` rejects `--enabled` followed by a path
      (`unknown option`); the linked plugin is enabled by default.
    - Trap: `~/.private_keys/AuthKey_<asc key id>.p8` is an App Store
      Connect API key, which APNs rejects (`InvalidProviderToken`).
