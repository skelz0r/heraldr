#!/bin/bash
set -u

here="$(cd "$(dirname "$0")" && pwd)"
dispatch="$here/../dispatch.sh"
failures=0

setup_world() {
  sandbox="$(mktemp -d)"
  export FAKE_HERDR_WORLD="$sandbox/world"
  export HERALDR_STATE_DIR="$sandbox/state"
  export HERALDR_CONFIG_DIR="$sandbox/config"
  mkdir -p "$sandbox/bin" "$FAKE_HERDR_WORLD/agents"
  ln -s "$here/fake-herdr" "$sandbox/bin/herdr"
  export PATH="$sandbox/bin:$ORIGINAL_PATH"
  /bin/sh "$dispatch" install < "$dispatch"
}

teardown_world() {
  pkill -f "$HERALDR_STATE_DIR/dispatch.sh" 2>/dev/null
  pkill -f "$sandbox/bin/herdr" 2>/dev/null
  rm -rf "$sandbox"
}

add_workspace() {
  mkdir -p "$FAKE_HERDR_WORLD/workspaces"
  printf '%s\t%s' "$2" "$3" > "$FAKE_HERDR_WORLD/workspaces/$1"
}

relay() {
  printf '%s' "$2" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" relay "$1" > /dev/null 2>&1
}

add_agent() {
  mkdir -p "$FAKE_HERDR_WORLD/agents/$1"
  echo "$2" > "$FAKE_HERDR_WORLD/agents/$1/workspace_id"
  echo "$3" > "$FAKE_HERDR_WORLD/agents/$1/status"
  echo session-initial > "$FAKE_HERDR_WORLD/agents/$1/session"
}

set_status() {
  echo "$2" > "$FAKE_HERDR_WORLD/agents/$1/status"
}

prompts_of() {
  cat "$FAKE_HERDR_WORLD/agents/$1/prompts" 2>/dev/null
}

enqueue() {
  printf '%s' "$3" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue "$1" "$(printf '%s' "$2" | base64)" > /dev/null
}

enqueue_pane() {
  printf '%s' "$4" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane "$1" "$2" "$3" > /dev/null
}

job_states() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f4 | tr '\n' ' '
}

wait_until() {
  deadline=$((SECONDS + $1))
  shift
  while [ $SECONDS -lt $deadline ]; do
    eval "$*" && return 0
    sleep 0.3
  done
  return 1
}

check() {
  if [ "$2" = "$3" ]; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1"
    echo "    expected: $(printf '%q' "$3")"
    echo "    actual:   $(printf '%q' "$2")"
    failures=$((failures + 1))
  fi
}

ORIGINAL_PATH="$PATH"

echo "a send to a busy agent waits until it is idle again"
setup_world
add_agent home-main w1 working
enqueue w1 '~' "My request"
sleep 3
check "nothing is sent while the agent works" "$(prompts_of home-main)" ""
check "the send is queued" "$(job_states)" "queued "
set_status home-main idle
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "as soon as it is idle: /clear then the request, never while working" "$(prompts_of home-main)" "idle|/clear
idle|My request"
teardown_world

echo "a send to a blocked agent waits until it is done"
setup_world
add_agent acme_app-main w2 blocked
enqueue w2 'acme_app' "Fix the bug"
sleep 3
check "nothing is sent while the agent waits for an answer" "$(prompts_of acme_app-main)" ""
set_status acme_app-main "done"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "as soon as it is done: /clear then the request" "$(prompts_of acme_app-main)" "done|/clear
done|Fix the bug"
teardown_world

echo "two sends to a busy agent go out in order, each after a /clear"
setup_world
add_agent home-main w1 working
enqueue w1 '~' "First"
sleep 1.1
enqueue w1 '~' "Second"
sleep 2
check "both are queued" "$(job_states)" "queued queued "
set_status home-main idle
wait_until 25 '[ "$(job_states)" = "sent sent " ]'
check "arrival order kept" "$(prompts_of home-main)" "idle|/clear
idle|First
idle|/clear
idle|Second"
teardown_world

echo "a missing agent is created in tab 1 of the workspace"
setup_world
enqueue w1 '~' "Cold request"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "split of the first pane of tab 1, in its cwd" "$(cat "$FAKE_HERDR_WORLD/splits")" "pane split w1:p1 --direction down --cwd /work/project --no-focus"
check "Claude in yolo mode with the Remote Control name home—main" "$(cat "$FAKE_HERDR_WORLD/starts")" "--kind claude --pane w1:p2 --timeout 60000 -- --dangerously-skip-permissions --remote-control home—main"
check "the request goes out after /clear" "$(prompts_of home-main)" "idle|/clear
idle|Cold request"
teardown_world

echo "an agent with the same name in another workspace is never targeted"
setup_world
add_agent home-main w9 idle
enqueue w1 '~' "Wrong target"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "the send fails without sending anything" "$(job_states)|$(prompts_of home-main)" "failed |"
check "the app reads the workspace, the agent, the state and the failure reason" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2-5)" "w1	home-main	failed	agent home-main belongs to workspace w9"
teardown_world

echo "a renamed workspace keeps its -main, whatever its name"
setup_world
add_agent herdr-ios-companion-main wH working
add_agent wH:pG wH idle
enqueue wH '📯 Heraldr' "After the rename"
add_workspace wH 6 '📯 Heraldr'
relay wH "Relayed"
sleep 2
set_status herdr-ios-companion-main idle
wait_until 25 '[ "$(job_states)" = "sent sent " ]'
check "the app send and the Home relay go to the existing agent" "$(prompts_of herdr-ios-companion-main | grep -c '^idle|/clear$')" "2"
check "no second Claude is started" "$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" ""
check "the unnamed Claude of the workspace receives nothing" "$(prompts_of wH:pG)" ""
teardown_world

echo "a -main renamed while a send waits for it is never duplicated"
setup_world
add_agent herdr-ios-companion-main wH working
mkdir -p "$HERALDR_STATE_DIR/locks/herdr-ios-companion-main"
echo $$ > "$HERALDR_STATE_DIR/locks/herdr-ios-companion-main/pid"
enqueue wH '📯 Heraldr' "Before the rename"
sleep 1
mv "$FAKE_HERDR_WORLD/agents/herdr-ios-companion-main" "$FAKE_HERDR_WORLD/agents/heraldr-main"
rm -rf "$HERALDR_STATE_DIR/locks/herdr-ios-companion-main"
/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" run herdr-ios-companion-main
check "the send fails without starting a second Claude" "$(job_states)|$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)|$(prompts_of heraldr-main)" "failed ||"
check "the reason names the current -main" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5)" "herdr-ios-companion-main is gone, the -main of wH is now heraldr-main: resend the request"
teardown_world

echo "the -main of another workspace is never targeted"
setup_world
add_agent apistration-main w9 idle
enqueue wH '📯 Heraldr' "For Heraldr"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "a -main is created in the target workspace" "$(cat "$FAKE_HERDR_WORLD/starts" | cut -d' ' -f4)|$(prompts_of heraldr-main)" "wH:p2|idle|/clear
idle|For Heraldr"
check "the one of the other workspace receives nothing" "$(prompts_of apistration-main)" ""
teardown_world

echo "with several -main in a workspace, only the one named after the label is targeted"
setup_world
add_agent local_events-main w8 idle
add_agent morris-main w8 idle
enqueue w8 '🟡 Morris' "For Morris"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "morris-main gets the request, not local_events-main" "$(prompts_of morris-main)|$(prompts_of local_events-main)" "idle|/clear
idle|For Morris|"
check "without a -main named after the label, the send is refused with the candidates" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w8 "$(printf 'Archives' | base64)" 2>&1; echo "code $?")" "several -main agents in w8: local_events-main morris-main
code 2"
check "nothing is queued or started" "$(job_states)|$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" "sent |"
teardown_world

echo "a send to the Claude of a tab goes out as is, without /clear or instructions"
setup_world
add_agent wB:pG wB idle
enqueue_pane wB wB:pG keep "The button is too small"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "the Claude of the tab gets the raw text, context kept" "$(prompts_of wB:pG)" "idle|The button is too small"
check "the app finds the send by its workspace and pane" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2-4)" "wB	wB:pG	sent"
check "no Claude is started" "$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" ""
teardown_world

echo "a send to a tab clears the context only when asked"
setup_world
add_agent wB:pG wB "done"
enqueue_pane wB wB:pG clear "Start over"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "/clear then the raw text" "$(prompts_of wB:pG)" "done|/clear
done|Start over"
teardown_world

echo "sends to a busy or blocked tab wait, in order"
setup_world
add_agent wB:pG wB blocked
enqueue_pane wB wB:pG keep "First feedback"
sleep 1.1
enqueue_pane wB wB:pG keep "Second feedback"
sleep 2
check "nothing is sent while it waits for an answer" "$(prompts_of wB:pG)|$(job_states)" "|queued queued "
set_status wB:pG working
sleep 2
check "nothing is sent while it works" "$(prompts_of wB:pG)" ""
set_status wB:pG idle
wait_until 15 '[ "$(job_states)" = "sent sent " ]'
check "arrival order kept, never while working" "$(prompts_of wB:pG)" "idle|First feedback
idle|Second feedback"
teardown_world

echo "a pane of another workspace or without Claude is never targeted"
setup_world
add_agent w9:p3 w9 idle
add_agent wB:p7 wB idle
echo codex > "$FAKE_HERDR_WORLD/agents/wB:p7/kind"
enqueue_pane wB w9:p3 keep "Wrong workspace"
enqueue_pane wB wB:pZ keep "Closed pane"
enqueue_pane wB wB:p7 keep "Not a Claude"
wait_until 10 '[ "$(job_states)" = "failed failed failed " ]'
check "nothing is sent or started" "$(prompts_of w9:p3)$(prompts_of wB:p7)$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" ""
check "the reason of each failure" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f3,5 | sort)" "w9:p3	pane w9:p3 belongs to workspace w9
wB:p7	no Claude left in pane wB:p7
wB:pZ	no Claude left in pane wB:pZ"
check "a malformed pane or an unknown option are refused" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB 'wB:p1;rm' keep 2>&1; echo $?)|$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB wB:p1 maybe >/dev/null 2>&1; echo $?)" "invalid pane: wB:p1;rm
2|2"
teardown_world

echo "a pane whose Claude is replaced while waiting receives nothing"
setup_world
add_agent wB:pG wB working
enqueue_pane wB wB:pG keep "For the old Claude"
sleep 2
echo codex > "$FAKE_HERDR_WORLD/agents/wB:pG/kind"
set_status wB:pG idle
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "the send fails without sending anything to the new agent" "$(job_states)|$(prompts_of wB:pG)" "failed |"
teardown_world

echo "the pane of a named agent is never targeted as a tab"
setup_world
add_agent wB:pG wB idle
echo acme-main > "$FAKE_HERDR_WORLD/agents/wB:pG/name"
enqueue_pane wB wB:pG keep "Bypass the main queue"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "the send fails without sending anything, the main queue stays the only one" "$(job_states)|$(prompts_of wB:pG)" "failed |"
check "the reason names the agent" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5)" "pane wB:pG is agent acme-main: target it by name"
teardown_world

echo "the iPhone registers its token and installs the notification hook"
setup_world
token="$(printf 'ab%.0s' $(seq 32))"
echo "// hook" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push "$token" sandbox com.example.heraldr.dev ABCDE12345
echo "// hook v2" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push "$token" sandbox com.example.heraldr.dev ABCDE12345
check "the token, the APNs environment, the topic and the team are kept" "$(cat "$HERALDR_STATE_DIR/push-device.json")" "{\"token\":\"$token\",\"env\":\"sandbox\",\"topic\":\"com.example.heraldr.dev\",\"team\":\"ABCDE12345\"}"
check "the hook is always the version sent by the app" "$(cat "$HERALDR_STATE_DIR/plugin/notify-hook.mjs")" "// hook v2"
check "the herdr plugin is linked only once" "$(cat "$FAKE_HERDR_WORLD/plugin_links")" "plugin link $HERALDR_STATE_DIR/plugin"
check "a malformed token is refused" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push 'abc;rm' sandbox t ABCDE12345 2>&1; echo $?)" "invalid token
2"
teardown_world

echo "Home relays a request to the -main of the project workspace, with the standard instructions"
setup_world
add_workspace w5 5 'Naïve search'
relay w5 "
  Add a subtitle
"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "the project agent is created in its workspace, named as the app does" "$(cat "$FAKE_HERDR_WORLD/starts")" "--kind claude --pane w5:p2 --timeout 60000 -- --dangerously-skip-permissions --remote-control Naïve search—main"
check "it gets /clear then the request without its surrounding blanks, as in the app, wrapped and ending with /start" "$(prompts_of naive-search-main)" "idle|/clear
idle|Request sent from the iPhone (may come from voice dictation: watch for transcription errors).

Add a subtitle

Instructions:
- explore the code to understand the request, change nothing here
- if the request is ambiguous, ask your questions with AskUserQuestion
- if it is a simple question with no work to do: answer without /start using \`/bin/sh \"\$HOME/.local/state/heraldr/dispatch.sh\" answer $(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f1)\`, with on standard input a one-sentence summary, a blank line, then the full answer in markdown
- otherwise, you must finish by dispatching the work with /start"
check "the send shows up in the project workspace" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2,3)" "w5	naive-search-main"
teardown_world

echo "an answer stays readable for a week, beyond the hour of other sends"
setup_world
add_agent home-main w1 idle
enqueue w1 '~' "How does the cache work?"
enqueue w1 '~' "Fix the cache"
wait_until 25 '[ "$(job_states)" = "sent sent " ]'
question="$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | head -1 | cut -f1)"
printf 'Cleared on deploy.\n\nDetails.\n' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" answer "$question" 2>/dev/null
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$HERALDR_STATE_DIR"/jobs/*/state
check "after two hours, only the answered question remains" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f1,4,6)" "$question	sent	answered"
touch -t "$(date -v-8d +%Y%m%d%H%M)" "$HERALDR_STATE_DIR/jobs/$question/answer"
check "after eight days, it is gone too" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status)" ""
teardown_world

echo "a send goes out only once Claude has started the previous one, never during its startup"
setup_world
add_agent home-main w1 idle
echo 3 > "$FAKE_HERDR_WORLD/agents/home-main/turn_seconds"
enqueue w1 '~' "First"
enqueue w1 '~' "Second"
wait_until 40 '[ "$(job_states)" = "sent sent " ]'
check "the /clear of the second waits for the work on the first to end" "$(prompts_of home-main)" "idle|/clear
idle|First
idle|/clear
idle|Second"
teardown_world

echo "a Claude that herdr takes more than 5 s to see working does not get the next /clear during its startup"
setup_world
export FAKE_HERDR_DETECTION_DELAY=7
add_agent home-main w1 idle
echo 2 > "$FAKE_HERDR_WORLD/agents/home-main/turn_seconds"
enqueue w1 '~' "Slow"
enqueue w1 '~' "Next"
wait_until 60 '[ "$(job_states)" = "sent sent " ]'
check "the /clear of the next one waits for the slow one to end" "$(prompts_of home-main)" "idle|/clear
idle|Slow
idle|/clear
idle|Next"
unset FAKE_HERDR_DETECTION_DELAY
teardown_world

echo "six sends in the same second go out in arrival order"
setup_world
add_agent wB:pG wB working
echo 0.3 > "$FAKE_HERDR_WORLD/agents/wB:pG/turn_seconds"
for request in one two three four five six; do
  enqueue_pane wB wB:pG keep "$request"
done
set_status wB:pG idle
wait_until 40 '[ "$(job_states)" = "sent sent sent sent sent sent " ]'
check "all six went out" "$(job_states)" "sent sent sent sent sent sent "
check "arrival order kept" "$(prompts_of wB:pG | cut -d '|' -f2 | tr '\n' ' ')" "one two three four five six "
teardown_world

echo "a send waits for the counter held by another send, even before that one wrote its pid"
setup_world
mkdir -p "$HERALDR_STATE_DIR/locks/sequence"
printf 'x' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB wB:pG keep > /dev/null 2>&1 &
sleep 1
check "no send created while the counter is taken" "$(job_states)" ""
rmdir "$HERALDR_STATE_DIR/locks/sequence"
wait_until 10 '[ -n "$(job_states)" ]'
check "the send is created as soon as the counter is released" "$(job_states | wc -w | tr -d ' ')" "1"
teardown_world

echo "an unreadable label, the old contract or an empty request create no send"
setup_world
check "empty label refused" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w1 '' 2>&1; echo $?)" "invalid label
2"
check "agent name passed by an older app refused" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w1 home-main "$(printf '~' | base64)" >/dev/null 2>&1; echo $?)" "2"
check "empty request refused" "$(printf '' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w1 "$(printf '~' | base64)" 2>&1; echo $?)" "empty prompt
2"
check "no send created" "$(job_states)" ""
teardown_world

echo "a Claude that does not start fails the send with the herdr reason"
setup_world
echo pane_not_ready > "$FAKE_HERDR_WORLD/start_error"
enqueue w1 '~' "Cold request"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "failure announced with the herdr reason" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f4)|$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5 | grep -o 'agent start: .*pane_not_ready')" "failed|agent start: {\"error\":{\"code\":\"pane_not_ready"
teardown_world

echo "a /clear without effect fails the send, without sending the request in the old context"
setup_world
export HERALDR_CLEAR_TIMEOUT_SECONDS=2
add_agent home-main w1 idle
touch "$FAKE_HERDR_WORLD/agents/home-main/ignores_clear"
enqueue w1 '~' "Clean context required"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "only the /clear went out" "$(prompts_of home-main)" "idle|/clear"
check "the reason says the context was not cleared" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5)" "/clear without a new session after 2s"
unset HERALDR_CLEAR_TIMEOUT_SECONDS
teardown_world

echo "the queue of an agent resumes after a dead runner that held its lock"
setup_world
add_agent home-main w1 idle
dead_pid="$(sh -c 'echo $$')"
mkdir -p "$HERALDR_STATE_DIR/locks/home-main"
echo "$dead_pid" > "$HERALDR_STATE_DIR/locks/home-main/pid"
enqueue w1 '~' "After the crash"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "the request goes out" "$(prompts_of home-main | tail -n 1)" "idle|After the crash"
teardown_world

echo "sent requests are forgotten after an hour, failures after a day"
setup_world
add_agent wB:pG wB idle
echo 0.1 > "$FAKE_HERDR_WORLD/agents/wB:pG/turn_seconds"
for request in recent old; do enqueue_pane wB wB:pG keep "$request"; done
for request in recent old; do enqueue_pane wB wB:pZ keep "$request"; done
wait_until 20 '[ "$(job_states | tr " " "\n" | sort | tr "\n" " ")" = " failed failed sent sent " ]'
age_job() {
  for job in "$HERALDR_STATE_DIR"/jobs/*; do
    if [ "$(cat "$job/agent")" = "$1" ] && grep -qx "$2" "$job/prompt"; then
      touch -t "$(date -v-"$3" +%Y%m%d%H%M)" "$job/state"
    fi
  done
}
age_job wB:pG recent 59M
age_job wB:pG old 61M
age_job wB:pZ recent 23H
age_job wB:pZ old 25H
check "the 59 min send and the 23 h failure remain" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f3,4 | sort | tr '\t\n' ' |')" "wB:pG sent|wB:pZ failed|"
teardown_world

echo "a relay to Home or to an unknown workspace is refused"
setup_world
add_workspace w1 1 'Home'
relay w1 "Loop"
check "relay to Home, workspace 1, refused" "$?" "2"
relay w404 "Lost"
check "relay to an unknown workspace refused" "$?" "2"
check "no send created" "$(job_states)" ""
teardown_world

echo "Home relays to the same agent the app would target for this workspace"
setup_world
number=2
while IFS="$(printf '\t')" read -r label agent; do
  add_workspace "w$number" "$number" "$label"
  relay "w$number" "Request"
  check "$label → $agent" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | awk -F '\t' -v w="w$number" '$2 == w { print $3 }')" "$agent"
  number=$((number + 1))
done < "$here/agent-names.tsv"
teardown_world

echo "a screenshot sent by the iPhone is kept on the Mac, readable by its path"
setup_world
printf 'fake jpeg' > "$sandbox/capture.jpg"
path="$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg < "$sandbox/capture.jpg")"
check "the returned path is absolute, under the state folder, with the extension" "$(printf '%s' "$path" | grep -Ec "^$HERALDR_STATE_DIR/attachments/[^/]+\.jpg$")" "1"
check "the file is the received image, intact" "$(cat "$path")" "fake jpeg"
check "an empty image or an unknown extension are refused" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg < /dev/null 2>&1; echo $?)|$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach 'sh;rm' 2>&1; echo $?)" "invalid attachment size: 0
2|invalid extension: sh;rm
2"
teardown_world

echo "a screenshot the Mac could not write is never announced as stored"
setup_world
mkdir -p "$HERALDR_STATE_DIR/attachments"
chmod 500 "$HERALDR_STATE_DIR/attachments"
output="$(echo image | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg 2>/dev/null)"
status=$?
chmod 700 "$HERALDR_STATE_DIR/attachments"
check "failure reported to the app, without path" "$status|$output" "1|"
teardown_world

echo "a screenshot stays available for a week, for a waiting send or a session started by /start"
setup_world
recent="$(echo recent | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach png)"
old="$(echo old | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach png)"
touch -t "$(date -v-6d +%Y%m%d%H%M)" "$recent"
touch -t "$(date -v-8d +%Y%m%d%H%M)" "$old"
/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status > /dev/null
check "the six-day screenshot is kept, the eight-day one deleted" "$([ -f "$recent" ] && echo kept)|$([ -f "$old" ] && echo kept)" "kept|"
teardown_world

echo "the iPhone lexicon is backed up on the Mac and read back as is"
setup_world
lexicon() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" "lexicon-$1"
}
check "without backup, nothing is read and it is not an error" "$(lexicon get; echo "code $?")" "code 0"
cat > "$sandbox/lexicon.json" <<'JSON'
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
JSON
lexicon put < "$sandbox/lexicon.json"
check "the write succeeds" "$?" "0"
lexicon get > "$sandbox/read-back.json"
check "read back byte for byte" "$(cmp -s "$sandbox/lexicon.json" "$sandbox/read-back.json" && echo identical)" "identical"
check "stored in ~/.config/heraldr" "$(cmp -s "$sandbox/lexicon.json" "$HERALDR_CONFIG_DIR/lexique.json" && echo identical)" "identical"
printf '{"version":1,"terms":[]}' | lexicon put
check "a new backup overwrites the previous one" "$(lexicon get)" '{"version":1,"terms":[]}'
check "a truncated upload is refused" "$(printf '{"version":1,"ter' | lexicon put 2>&1; echo "code $?")" "unreadable lexicon
code 2"
check "a version that is not an integer is refused" "$(printf '{"version":"1","terms":[]}' | lexicon put 2>&1; echo "code $?")" "unreadable lexicon
code 2"
check "an empty upload is refused" "$(lexicon put < /dev/null 2>&1; echo "code $?")" "unreadable lexicon
code 2"
check "the previous backup stays intact, without temporary file" "$(lexicon get; ls "$HERALDR_CONFIG_DIR")" '{"version":1,"terms":[]}lexique.json'
teardown_world

echo "the dictation journal is appended on the Mac, without duplicate or damaged entry"
setup_world
journal_append() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" journal-append
}
journal="$HERALDR_CONFIG_DIR/journal-dictees.jsonl"
first='{"id":"A1","salves":[{"edited":"Run Acme.","proposed":"Run Acme.","raw":"run ack me"}],"sent":"Run Acme.","version":1}'
second='{"id":"B2","salves":[],"sent":"Open the PR.","version":1}'
check "without journal, the first upload creates it" "$(printf '%s\n' "$first" | journal_append; echo "code $?"; cat "$journal")" "code 0
$first"
check "a next upload is appended at the end, an entry already received is not duplicated" "$(printf '%s\n%s\n' "$first" "$second" | journal_append; echo "code $?"; cat "$journal")" "code 0
$first
$second"
check "a truncated entry refuses the whole upload" "$(printf '%s\n{"id":"C3","version":1,"se\n' '{"id":"D4","version":1}' | journal_append 2>&1; echo "code $?")" "unreadable journal
code 2"
check "an entry without an integer version is refused" "$(printf '{"id":"C3","version":"1"}\n' | journal_append 2>&1; echo "code $?")" "unreadable journal
code 2"
check "an entry without a readable id is refused" "$(printf '{"id":"a b","version":1}\n' | journal_append 2>&1; echo "code $?")" "unreadable journal
code 2"
check "an empty upload is refused" "$(journal_append < /dev/null 2>&1; echo "code $?")" "unreadable journal
code 2"
check "an entry whose id holds a line break is refused" "$(printf '{"id":"A1\\n.*","version":1}\n' | journal_append 2>&1; echo "code $?")" "unreadable journal
code 2"
check "an entry that is not JSON is refused" "$(printf '<plist version="1.0"><dict><key>version</key><integer>1</integer><key>id</key><string>X1</string></dict></plist>\n' | journal_append 2>&1; echo "code $?")" "unreadable journal
code 2"
check "the journal stays intact, without temporary file" "$(cat "$journal"; ls "$HERALDR_CONFIG_DIR")" "$first
$second
journal-dictees.jsonl"
printf '%s' "$first" > "$journal"
printf '%s\n' "$second" | journal_append
check "a journal without final line break stays one line per entry" "$(cat "$journal")" "$first
$second"
rm "$journal"
for n in 1 2 3 4 5 6 7 8; do
  printf '{"id":"P%s","version":1}\n' "$n" | journal_append &
done
wait
check "simultaneous appends keep every entry" "$(sort "$journal" | tr -d '\n')" '{"id":"P1","version":1}{"id":"P2","version":1}{"id":"P3","version":1}{"id":"P4","version":1}{"id":"P5","version":1}{"id":"P6","version":1}{"id":"P7","version":1}{"id":"P8","version":1}'
teardown_world

if [ $failures -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all cases pass"
