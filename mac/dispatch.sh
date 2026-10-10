#!/bin/sh
set -u

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin"
export PATH

STATE_DIR="${HERALDR_STATE_DIR:-$HOME/.local/state/heraldr}"
JOBS_DIR="$STATE_DIR/jobs"
LOCKS_DIR="$STATE_DIR/locks"
SCRIPT_PATH="$STATE_DIR/dispatch.sh"
SENT_RETENTION_MINUTES=60
FAILED_RETENTION_MINUTES=1440
CLEAR_TIMEOUT_SECONDS=20
START_TIMEOUT_MS=60000

json_value() {
  plutil -extract "$1" raw -o - - 2>/dev/null
}

fail_usage() {
  echo "usage: dispatch.sh install | enqueue <workspace_id> <agent> <label_base64> | run <agent> | status" >&2
  exit 2
}

install_script() {
  mkdir -p "$STATE_DIR"
  temporary="$SCRIPT_PATH.$$"
  cat > "$temporary" && chmod 755 "$temporary" && mv "$temporary" "$SCRIPT_PATH"
}

valid_agent_name() {
  printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9_-]{0,31}$'
}

enqueue_job() {
  workspace_id="$1"
  agent="$2"
  label="$(printf '%s' "$3" | base64 -d 2>/dev/null)" || label=""
  valid_agent_name "$agent" || { echo "invalid agent name: $agent" >&2; exit 2; }
  [ -n "$label" ] || { echo "invalid label" >&2; exit 2; }

  job_id="$(date -u +%Y%m%d%H%M%S)-$$-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  job_dir="$JOBS_DIR/$job_id"
  mkdir -p "$job_dir.tmp"
  cat > "$job_dir.tmp/prompt"
  if [ ! -s "$job_dir.tmp/prompt" ]; then
    rm -rf "$job_dir.tmp"
    echo "empty prompt" >&2
    exit 2
  fi
  printf '%s' "$workspace_id" > "$job_dir.tmp/workspace_id"
  printf '%s' "$agent" > "$job_dir.tmp/agent"
  printf '%s' "$label" > "$job_dir.tmp/label"
  printf 'queued' > "$job_dir.tmp/state"
  mv "$job_dir.tmp" "$job_dir"

  nohup /bin/sh "$SCRIPT_PATH" run "$agent" </dev/null >/dev/null 2>&1 &
  echo "$job_id"
}

set_state() {
  printf '%s' "$2" > "$1/state.tmp" && mv "$1/state.tmp" "$1/state"
}

fail_job() {
  printf '%s' "$2" > "$1/error"
  set_state "$1" failed
}

acquire_lock() {
  lock="$LOCKS_DIR/$1"
  mkdir -p "$LOCKS_DIR"
  if mkdir "$lock" 2>/dev/null; then
    echo $$ > "$lock/pid"
    return 0
  fi
  holder="$(cat "$lock/pid" 2>/dev/null)"
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    return 1
  fi
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null || return 1
  echo $$ > "$lock/pid"
}

release_lock() {
  rm -rf "$LOCKS_DIR/$1"
}

next_job_for() {
  for job_dir in "$JOBS_DIR"/*; do
    [ -d "$job_dir" ] || continue
    case "$job_dir" in *.tmp) continue ;; esac
    [ "$(cat "$job_dir/agent" 2>/dev/null)" = "$1" ] || continue
    [ "$(cat "$job_dir/state" 2>/dev/null)" = "queued" ] || continue
    echo "$job_dir"
    return 0
  done
  return 1
}

first_tab_id() {
  tabs="$(herdr tab list --workspace "$1")" || return 1
  index=0
  while number="$(printf '%s' "$tabs" | json_value "result.tabs.$index.number")"; do
    if [ "$number" = "1" ]; then
      printf '%s' "$tabs" | json_value "result.tabs.$index.tab_id"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

first_pane_of_tab() {
  panes="$(herdr pane list --workspace "$1")" || return 1
  index=0
  while tab_id="$(printf '%s' "$panes" | json_value "result.panes.$index.tab_id")"; do
    if [ "$tab_id" = "$2" ]; then
      printf '%s' "$panes" | json_value "result.panes.$index.$3"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

agent_field() {
  herdr agent get "$1" 2>/dev/null | json_value "result.agent.$2"
}

start_agent() {
  job_dir="$1"
  workspace_id="$2"
  agent="$3"
  label="$4"

  tab_id="$(first_tab_id "$workspace_id")" || { fail_job "$job_dir" "tab 1 introuvable dans $workspace_id"; return 1; }
  anchor_pane="$(first_pane_of_tab "$workspace_id" "$tab_id" pane_id)" || { fail_job "$job_dir" "aucun pane dans $tab_id"; return 1; }
  cwd="$(first_pane_of_tab "$workspace_id" "$tab_id" cwd)" || cwd="$HOME"
  split="$(herdr pane split "$anchor_pane" --direction down --cwd "$cwd" --no-focus 2>&1)" || { fail_job "$job_dir" "pane split: $split"; return 1; }
  pane_id="$(printf '%s' "$split" | json_value result.pane.pane_id)" || { fail_job "$job_dir" "pane split sans pane_id"; return 1; }

  remote_control_name="$(printf '%s' "$label" | sed 's/^~$/home/')—main"
  started="$(herdr agent start "$agent" --kind claude --pane "$pane_id" --timeout "$START_TIMEOUT_MS" -- --dangerously-skip-permissions --remote-control "$remote_control_name" 2>&1)"
  if [ $? -ne 0 ]; then
    case "$started" in
      *agent_not_ready*) return 0 ;;
    esac
    fail_job "$job_dir" "agent start: $started"
    return 1
  fi
}

wait_for_clear() {
  previous_session="$2"
  waited=0
  while [ "$waited" -lt "$CLEAR_TIMEOUT_SECONDS" ]; do
    sleep 1
    waited=$((waited + 1))
    current_session="$(agent_field "$1" agent_session.value)"
    if [ -n "$current_session" ] && [ "$current_session" != "$previous_session" ]; then
      return 0
    fi
  done
  [ -z "$previous_session" ]
}

process_job() {
  job_dir="$1"
  agent="$(cat "$job_dir/agent")"
  workspace_id="$(cat "$job_dir/workspace_id")"
  label="$(cat "$job_dir/label")"

  agent_workspace="$(agent_field "$agent" workspace_id)"
  if [ -z "$agent_workspace" ]; then
    start_agent "$job_dir" "$workspace_id" "$agent" "$label" || return 1
  elif [ "$agent_workspace" != "$workspace_id" ]; then
    fail_job "$job_dir" "l'agent $agent appartient au workspace $agent_workspace"
    return 1
  fi

  waited="$(herdr agent wait "$agent" --until idle --until done 2>&1)" || { fail_job "$job_dir" "agent wait: $waited"; return 1; }

  set_state "$job_dir" sending
  session_before="$(agent_field "$agent" agent_session.value)"
  cleared="$(herdr agent prompt "$agent" "/clear" 2>&1)" || { fail_job "$job_dir" "/clear: $cleared"; return 1; }
  wait_for_clear "$agent" "$session_before" || { fail_job "$job_dir" "/clear sans nouvelle session après ${CLEAR_TIMEOUT_SECONDS}s"; return 1; }
  sleep 1

  prompted="$(herdr agent prompt "$agent" "$(cat "$job_dir/prompt")" 2>&1)" || { fail_job "$job_dir" "prompt: $prompted"; return 1; }
  date -u +%Y-%m-%dT%H:%M:%SZ > "$job_dir/sent_at"
  set_state "$job_dir" sent
}

prune_jobs() {
  [ -d "$JOBS_DIR" ] || return 0
  find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -name state -mmin +"$SENT_RETENTION_MINUTES" -exec grep -lx sent {} + 2>/dev/null | while read -r state_file; do
    rm -rf "$(dirname "$state_file")"
  done
  find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -name state -mmin +"$FAILED_RETENTION_MINUTES" -exec grep -lx failed {} + 2>/dev/null | while read -r state_file; do
    rm -rf "$(dirname "$state_file")"
  done
}

run_agent_queue() {
  agent="$1"
  valid_agent_name "$agent" || exit 2
  while acquire_lock "$agent"; do
    while job_dir="$(next_job_for "$agent")"; do
      process_job "$job_dir"
    done
    release_lock "$agent"
    next_job_for "$agent" >/dev/null || break
  done
  prune_jobs
}

print_status() {
  prune_jobs
  [ -d "$JOBS_DIR" ] || return 0
  for job_dir in "$JOBS_DIR"/*; do
    [ -d "$job_dir" ] || continue
    case "$job_dir" in *.tmp) continue ;; esac
    error=""
    [ -f "$job_dir/error" ] && error="$(tr '\t\n' '  ' < "$job_dir/error")"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(basename "$job_dir")" \
      "$(cat "$job_dir/workspace_id" 2>/dev/null)" \
      "$(cat "$job_dir/agent" 2>/dev/null)" \
      "$(cat "$job_dir/state" 2>/dev/null)" \
      "$error"
  done
}

[ $# -ge 1 ] || fail_usage
command="$1"
shift
case "$command" in
  install) install_script ;;
  enqueue) [ $# -eq 3 ] || fail_usage; enqueue_job "$@" ;;
  run) [ $# -eq 1 ] || fail_usage; run_agent_queue "$1" ;;
  status) print_status ;;
  *) fail_usage ;;
esac
