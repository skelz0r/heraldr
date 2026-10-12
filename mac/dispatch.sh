#!/bin/sh
set -u

PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.cargo/bin"
export PATH

STATE_DIR="${HERALDR_STATE_DIR:-$HOME/.local/state/heraldr}"
JOBS_DIR="$STATE_DIR/jobs"
LOCKS_DIR="$STATE_DIR/locks"
ATTACHMENTS_DIR="$STATE_DIR/attachments"
SCRIPT_PATH="$STATE_DIR/dispatch.sh"
PLUGIN_DIR="$STATE_DIR/plugin"
PUSH_DEVICE_PATH="$STATE_DIR/push-device.json"
LEXICON_PATH="${HERALDR_CONFIG_DIR:-$HOME/.config/heraldr}/lexique.json"
JOURNAL_PATH="${HERALDR_CONFIG_DIR:-$HOME/.config/heraldr}/journal-dictees.jsonl"
JOURNAL_LOCK="journal.dictees"
SENT_RETENTION_MINUTES=60
FAILED_RETENTION_MINUTES=1440
ATTACHMENT_RETENTION_MINUTES=10080
ATTACHMENT_MAX_BYTES=20000000
ANSWERED_RETENTION_MINUTES=10080
CLEAR_TIMEOUT_SECONDS="${HERALDR_CLEAR_TIMEOUT_SECONDS:-20}"
PROMPT_START_TIMEOUT_MS=10000
STALLED_PROMPT_GRACE_MS=30000
SEQUENCE_LOCK_STALE_MINUTES=1
START_TIMEOUT_MS=60000

json_value() {
  plutil -extract "$1" raw -o - - 2>/dev/null
}

fail_usage() {
  echo "usage: dispatch.sh install | enqueue <workspace_id> <agent> <label_base64> | enqueue-pane <workspace_id> <pane_id> <clear|keep> | relay <workspace_id> | attach <jpg|png> | answer <job_id> | read-answer <job_id> | run <agent> | status | register-push <token> <sandbox|production> <topic> <team_id> | lexicon-get | lexicon-put | journal-append" >&2
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

valid_pane_id() {
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9]+:[A-Za-z0-9]+$'
}

valid_queue_target() {
  valid_agent_name "$1" || valid_pane_id "$1"
}

lock_name() {
  printf '%s' "$1" | tr ':' '@'
}

agent_name_for_label() {
  slug="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | LC_ALL=en_US.UTF-8 sed 's/[^abcdefghijklmnopqrstuvwxyz0123456789_-]/-/g')"
  case "$slug" in
    [abcdefghijklmnopqrstuvwxyz]*) ;;
    *) slug="w-$slug" ;;
  esac
  printf '%s-main' "$(printf '%s' "$slug" | cut -c1-27)"
}

standard_envelope() {
  cat <<EOF
Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : attention aux erreurs de transcription).

$1

Consignes :
- explore le code pour comprendre la demande, ne modifie rien ici
- si la demande est ambiguë, pose tes questions avec AskUserQuestion
- si c'est une simple question, sans travail à faire : réponds sans /start avec \`/bin/sh "\$HOME/.local/state/heraldr/dispatch.sh" answer {{job_id}}\`, sur l'entrée standard un résumé d'une phrase, une ligne vide puis la réponse complète en markdown
- sinon, termine obligatoirement en dispatchant le travail avec /start
EOF
}

enqueue_job() {
  valid_agent_name "$2" || { echo "invalid agent name: $2" >&2; exit 2; }
  label="$(printf '%s' "$3" | base64 -d 2>/dev/null)" || label=""
  create_job "$1" "$2" "$label" clear
}

enqueue_pane_job() {
  valid_pane_id "$2" || { echo "invalid pane: $2" >&2; exit 2; }
  case "$3" in clear|keep) ;; *) fail_usage ;; esac
  create_job "$1" "$2" "$2" "$3"
}

relay_job() {
  workspace_id="$1"
  workspace="$(herdr workspace get "$workspace_id" 2>&1)" || { echo "workspace introuvable: $workspace_id" >&2; exit 2; }
  label="$(printf '%s' "$workspace" | json_value result.workspace.label)" || { echo "workspace sans label: $workspace_id" >&2; exit 2; }
  [ "$(printf '%s' "$workspace" | json_value result.workspace.number)" != "1" ] || { echo "relais vers Home impossible" >&2; exit 2; }
  request="$(cat)"
  [ -n "$request" ] || { echo "empty prompt" >&2; exit 2; }
  standard_envelope "$request" | create_job "$workspace_id" "$(agent_name_for_label "$label")" "$label" clear
}

create_job() {
  workspace_id="$1"
  agent="$2"
  label="$3"
  clear="$4"
  valid_queue_target "$agent" || { echo "invalid agent name: $agent" >&2; exit 2; }
  [ -n "$label" ] || { echo "invalid label" >&2; exit 2; }

  job_id="$(date -u +%Y%m%d%H%M%S)-$(next_sequence)-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  job_dir="$JOBS_DIR/$job_id"
  mkdir -p "$job_dir.tmp"
  sed "s/{{job_id}}/$job_id/g" > "$job_dir.tmp/prompt"
  if [ ! -s "$job_dir.tmp/prompt" ]; then
    rm -rf "$job_dir.tmp"
    echo "empty prompt" >&2
    exit 2
  fi
  printf '%s' "$workspace_id" > "$job_dir.tmp/workspace_id"
  printf '%s' "$agent" > "$job_dir.tmp/agent"
  printf '%s' "$label" > "$job_dir.tmp/label"
  printf '%s' "$clear" > "$job_dir.tmp/clear"
  printf 'queued' > "$job_dir.tmp/state"
  mv "$job_dir.tmp" "$job_dir"

  nohup /bin/sh "$SCRIPT_PATH" run "$agent" </dev/null >/dev/null 2>&1 &
  echo "$job_id"
}

store_attachment() {
  case "$1" in jpg|png) ;; *) echo "invalid extension: $1" >&2; exit 2 ;; esac
  mkdir -p "$ATTACHMENTS_DIR" || { echo "attachments dir unavailable" >&2; exit 1; }
  attachment="$ATTACHMENTS_DIR/$(date -u +%Y%m%d%H%M%S)-$$-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n').$1"
  cat > "$attachment.tmp" || { rm -f "$attachment.tmp"; echo "attachment write failed" >&2; exit 1; }
  size="$(wc -c < "$attachment.tmp" | tr -d ' ')"
  if [ "$size" -eq 0 ] || [ "$size" -gt "$ATTACHMENT_MAX_BYTES" ]; then
    rm -f "$attachment.tmp"
    echo "invalid attachment size: $size" >&2
    exit 2
  fi
  mv "$attachment.tmp" "$attachment" || { rm -f "$attachment.tmp"; echo "attachment write failed" >&2; exit 1; }
  echo "$attachment"
}

next_sequence() {
  mkdir -p "$LOCKS_DIR"
  until mkdir "$LOCKS_DIR/sequence" 2>/dev/null; do
    [ -n "$(find "$LOCKS_DIR/sequence" -maxdepth 0 -mmin +"$SEQUENCE_LOCK_STALE_MINUTES" 2>/dev/null)" ] && rmdir "$LOCKS_DIR/sequence" 2>/dev/null
    sleep 0.05
  done
  sequence=$(( $(cat "$STATE_DIR/sequence" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$sequence" > "$STATE_DIR/sequence"
  rmdir "$LOCKS_DIR/sequence"
  printf '%012d' "$sequence"
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

check_pane_target() {
  pane="$(herdr agent get "$2" 2>/dev/null)"
  [ "$(printf '%s' "$pane" | json_value result.agent.agent)" = "claude" ] || { fail_job "$1" "plus de Claude dans le pane $2"; return 1; }
  pane_workspace="$(printf '%s' "$pane" | json_value result.agent.workspace_id)"
  [ "$pane_workspace" = "$3" ] || { fail_job "$1" "le pane $2 appartient au workspace $pane_workspace"; return 1; }
  pane_name="$(printf '%s' "$pane" | json_value result.agent.name)"
  [ -z "$pane_name" ] || { fail_job "$1" "le pane $2 est l'agent $pane_name : vise-le par son nom"; return 1; }
}

process_job() {
  job_dir="$1"
  agent="$(cat "$job_dir/agent")"
  workspace_id="$(cat "$job_dir/workspace_id")"
  label="$(cat "$job_dir/label")"
  clear="$(cat "$job_dir/clear" 2>/dev/null || echo clear)"

  agent_workspace="$(agent_field "$agent" workspace_id)"
  if valid_pane_id "$agent"; then
    check_pane_target "$job_dir" "$agent" "$workspace_id" || return 1
  elif [ -z "$agent_workspace" ]; then
    start_agent "$job_dir" "$workspace_id" "$agent" "$label" || return 1
  elif [ "$agent_workspace" != "$workspace_id" ]; then
    fail_job "$job_dir" "l'agent $agent appartient au workspace $agent_workspace"
    return 1
  fi

  waited="$(herdr agent wait "$agent" --until idle --until done 2>&1)" || { fail_job "$job_dir" "agent wait: $waited"; return 1; }

  if valid_pane_id "$agent"; then
    check_pane_target "$job_dir" "$agent" "$workspace_id" || return 1
  fi

  set_state "$job_dir" sending
  if [ "$clear" = "clear" ]; then
    session_before="$(agent_field "$agent" agent_session.value)"
    cleared="$(herdr agent prompt "$agent" "/clear" 2>&1)" || { fail_job "$job_dir" "/clear: $cleared"; return 1; }
    wait_for_clear "$agent" "$session_before" || { fail_job "$job_dir" "/clear sans nouvelle session après ${CLEAR_TIMEOUT_SECONDS}s"; return 1; }
    sleep 1
  fi

  prompted="$(herdr agent prompt "$agent" "$(cat "$job_dir/prompt")" --wait --until working --until blocked --timeout "$PROMPT_START_TIMEOUT_MS" 2>&1)" || case "$prompted" in
    *agent_prompt_stalled*) herdr agent wait "$agent" --until working --until blocked --timeout "$STALLED_PROMPT_GRACE_MS" >/dev/null 2>&1 ;;
    *) fail_job "$job_dir" "prompt: $prompted"; return 1 ;;
  esac
  date -u +%Y-%m-%dT%H:%M:%SZ > "$job_dir/sent_at"
  set_state "$job_dir" sent
}

prune_jobs() {
  [ -d "$ATTACHMENTS_DIR" ] && find "$ATTACHMENTS_DIR" -type f -mmin +"$ATTACHMENT_RETENTION_MINUTES" -delete 2>/dev/null
  [ -d "$JOBS_DIR" ] || return 0
  find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -name state -mmin +"$SENT_RETENTION_MINUTES" -exec grep -lx sent {} + 2>/dev/null | while read -r state_file; do
    [ -f "$(dirname "$state_file")/answer" ] || rm -rf "$(dirname "$state_file")"
  done
  find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -name answer -mmin +"$ANSWERED_RETENTION_MINUTES" 2>/dev/null | while read -r answer_file; do
    rm -rf "$(dirname "$answer_file")"
  done
  find "$JOBS_DIR" -mindepth 2 -maxdepth 2 -name state -mmin +"$FAILED_RETENTION_MINUTES" -exec grep -lx failed {} + 2>/dev/null | while read -r state_file; do
    rm -rf "$(dirname "$state_file")"
  done
}

run_agent_queue() {
  agent="$1"
  valid_queue_target "$agent" || exit 2
  queue_lock="$(lock_name "$agent")"
  while acquire_lock "$queue_lock"; do
    while job_dir="$(next_job_for "$agent")"; do
      process_job "$job_dir"
    done
    release_lock "$queue_lock"
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
    answered=""
    [ -f "$job_dir/answer" ] && answered="answered"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(basename "$job_dir")" \
      "$(cat "$job_dir/workspace_id" 2>/dev/null)" \
      "$(cat "$job_dir/agent" 2>/dev/null)" \
      "$(cat "$job_dir/state" 2>/dev/null)" \
      "$error" \
      "$answered"
  done
}

answered_job_dir() {
  printf '%s' "$1" | grep -Eq '^[0-9]{14}-[0-9]+-[0-9a-f]{8}$' || { echo "invalid job id: $1" >&2; exit 2; }
  [ -d "$JOBS_DIR/$1" ] || { echo "job inconnu: $1" >&2; exit 2; }
  printf '%s' "$JOBS_DIR/$1"
}

store_answer() {
  job_dir="$(answered_job_dir "$1")" || exit 2
  cat > "$job_dir/answer.tmp"
  if [ -z "$(head -n 1 "$job_dir/answer.tmp" | tr -d '[:space:]')" ]; then
    rm -f "$job_dir/answer.tmp"
    echo "réponse vide ou sans résumé en première ligne" >&2
    exit 2
  fi
  mv "$job_dir/answer.tmp" "$job_dir/answer"
  [ -f "$PUSH_DEVICE_PATH" ] && [ -f "$PLUGIN_DIR/notify-hook.mjs" ] || { echo "réponse gardée, pas de notification : aucun iPhone enregistré" >&2; return 0; }
  pushed="$(node "$PLUGIN_DIR/notify-hook.mjs" answer "$1" 2>&1)" || echo "réponse gardée, notification non envoyée : $pushed" >&2
}

print_answer() {
  job_dir="$(answered_job_dir "$1")" || exit 2
  [ -f "$job_dir/answer" ] || { echo "pas de réponse pour $1" >&2; exit 2; }
  cat "$job_dir/answer"
}

install_notify_plugin() {
  mkdir -p "$PLUGIN_DIR"
  cat > "$PLUGIN_DIR/notify-hook.mjs.tmp" && mv "$PLUGIN_DIR/notify-hook.mjs.tmp" "$PLUGIN_DIR/notify-hook.mjs"
  cat > "$PLUGIN_DIR/herdr-plugin.toml" <<'MANIFEST'
id = "heraldr"
name = "Heraldr"
version = "0.1.0"
min_herdr_version = "0.9.3"
description = "Push Heraldr quand un agent -main attend une réponse"
platforms = ["macos"]

[[events]]
on = "pane.agent_status_changed"
command = ["node", "notify-hook.mjs"]
MANIFEST
  herdr plugin list 2>/dev/null | grep -q '^- heraldr ' && return 0
  linked="$(herdr plugin link "$PLUGIN_DIR" 2>&1)" || { echo "plugin link: $linked" >&2; return 1; }
}

register_push_device() {
  printf '%s' "$1" | grep -Eq '^[0-9a-f]{64,200}$' || { echo "invalid token" >&2; exit 2; }
  case "$2" in sandbox|production) ;; *) echo "invalid environment: $2" >&2; exit 2 ;; esac
  printf '%s' "$3" | grep -Eq '^[A-Za-z0-9.-]+$' || { echo "invalid topic: $3" >&2; exit 2; }
  printf '%s' "$4" | grep -Eq '^[A-Z0-9]{10}$' || { echo "invalid team id: $4" >&2; exit 2; }
  install_notify_plugin || exit 1
  mkdir -p "$STATE_DIR"
  printf '{"token":"%s","env":"%s","topic":"%s","team":"%s"}\n' "$1" "$2" "$3" "$4" > "$PUSH_DEVICE_PATH.tmp"
  mv "$PUSH_DEVICE_PATH.tmp" "$PUSH_DEVICE_PATH"
}

print_lexicon() {
  [ ! -f "$LEXICON_PATH" ] || cat "$LEXICON_PATH"
}

store_lexicon() {
  mkdir -p "$(dirname "$LEXICON_PATH")"
  temporary="$LEXICON_PATH.$$"
  cat > "$temporary"
  if ! plutil -type version -expect integer "$temporary" > /dev/null 2>&1; then
    rm -f "$temporary"
    echo "lexique illisible" >&2
    exit 2
  fi
  mv "$temporary" "$LEXICON_PATH" || { rm -f "$temporary"; exit 1; }
}

reject_journal() {
  rm -f "$incoming" "$entry" "$fresh"
  release_lock "$JOURNAL_LOCK"
  echo "journal illisible" >&2
  exit 2
}

fail_journal() {
  rm -f "$incoming" "$entry" "$fresh"
  release_lock "$JOURNAL_LOCK"
  exit 1
}

append_journal() {
  mkdir -p "$(dirname "$JOURNAL_PATH")"
  incoming="$JOURNAL_PATH.in.$$"
  entry="$JOURNAL_PATH.entry.$$"
  fresh="$JOURNAL_PATH.new.$$"
  cat > "$incoming"
  attempts=0
  until acquire_lock "$JOURNAL_LOCK"; do
    attempts=$((attempts + 1))
    [ $attempts -lt 50 ] || { rm -f "$incoming"; echo "journal occupé" >&2; exit 1; }
    sleep 0.2
  done
  [ -s "$incoming" ] || reject_journal
  touch "$JOURNAL_PATH" && : > "$fresh" || fail_journal
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "{"*) ;; *) reject_journal ;; esac
    printf '%s' "$line" > "$entry" || fail_journal
    plutil -type version -expect integer "$entry" > /dev/null 2>&1 || reject_journal
    id="$(plutil -extract id raw -expect string -o - "$entry" 2>/dev/null)"
    case "$id" in "" | *[!A-Za-z0-9-]*) reject_journal ;; esac
    [ ${#id} -le 64 ] || reject_journal
    grep -Eq "\"id\" *: *\"$id\"" "$JOURNAL_PATH" "$fresh"
    case $? in
      0) ;;
      1) printf '%s\n' "$line" >> "$fresh" || fail_journal ;;
      *) fail_journal ;;
    esac
  done < "$incoming"
  if [ -s "$JOURNAL_PATH" ] && [ "$(tail -c 1 "$JOURNAL_PATH" | od -An -c | tr -d ' ')" != '\n' ]; then
    printf '\n' >> "$JOURNAL_PATH" || fail_journal
  fi
  cat "$fresh" >> "$JOURNAL_PATH" || fail_journal
  rm -f "$incoming" "$entry" "$fresh"
  release_lock "$JOURNAL_LOCK"
}

[ $# -ge 1 ] || fail_usage
command="$1"
shift
case "$command" in
  install) install_script ;;
  enqueue) [ $# -eq 3 ] || fail_usage; enqueue_job "$@" ;;
  enqueue-pane) [ $# -eq 3 ] || fail_usage; enqueue_pane_job "$@" ;;
  relay) [ $# -eq 1 ] || fail_usage; relay_job "$1" ;;
  attach) [ $# -eq 1 ] || fail_usage; store_attachment "$1" ;;
  answer) [ $# -eq 1 ] || fail_usage; store_answer "$1" ;;
  read-answer) [ $# -eq 1 ] || fail_usage; print_answer "$1" ;;
  run) [ $# -eq 1 ] || fail_usage; run_agent_queue "$1" ;;
  status) print_status ;;
  register-push) [ $# -eq 4 ] || fail_usage; register_push_device "$@" ;;
  lexicon-get) [ $# -eq 0 ] || fail_usage; print_lexicon ;;
  lexicon-put) [ $# -eq 0 ] || fail_usage; store_lexicon ;;
  journal-append) [ $# -eq 0 ] || fail_usage; append_journal ;;
  *) fail_usage ;;
esac
