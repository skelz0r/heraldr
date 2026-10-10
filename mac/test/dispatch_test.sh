#!/bin/bash
set -u

here="$(cd "$(dirname "$0")" && pwd)"
dispatch="$here/../dispatch.sh"
failures=0

setup_world() {
  sandbox="$(mktemp -d)"
  export FAKE_HERDR_WORLD="$sandbox/world"
  export HERALDR_STATE_DIR="$sandbox/state"
  mkdir -p "$sandbox/bin" "$FAKE_HERDR_WORLD/agents"
  ln -s "$here/fake-herdr" "$sandbox/bin/herdr"
  export PATH="$sandbox/bin:$ORIGINAL_PATH"
  /bin/sh "$dispatch" install < "$dispatch"
}

teardown_world() {
  pkill -f "$HERALDR_STATE_DIR/dispatch.sh" 2>/dev/null
  rm -rf "$sandbox"
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
  printf '%s' "$4" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue "$1" "$2" "$(printf '%s' "$3" | base64)" > /dev/null
}

job_states() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f4 | tr '\n' ' '
}

wait_until() {
  deadline=$((SECONDS + $1))
  shift
  while [ $SECONDS -lt $deadline ]; do
    eval "$@" && return 0
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

echo "un envoi vers un agent occupé attend qu'il redevienne idle"
setup_world
add_agent home-main w1 working
enqueue w1 home-main '~' "Ma demande"
sleep 3
check "rien n'est envoyé pendant que l'agent travaille" "$(prompts_of home-main)" ""
check "l'envoi est en attente" "$(job_states)" "queued "
set_status home-main idle
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "dès qu'il est idle : /clear puis la demande, jamais en working" "$(prompts_of home-main)" "idle|/clear
idle|Ma demande"
teardown_world

echo "un envoi vers un agent bloqué attend qu'il ait fini"
setup_world
add_agent acme_app-main w2 blocked
enqueue w2 acme_app-main 'acme_app' "Corrige le bug"
sleep 3
check "rien n'est envoyé pendant que l'agent attend une réponse" "$(prompts_of acme_app-main)" ""
set_status acme_app-main done
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "dès qu'il est done : /clear puis la demande" "$(prompts_of acme_app-main)" "done|/clear
done|Corrige le bug"
teardown_world

echo "deux envois vers un agent occupé partent dans l'ordre, chacun après un /clear"
setup_world
add_agent home-main w1 working
enqueue w1 home-main '~' "Première"
sleep 1.1
enqueue w1 home-main '~' "Seconde"
sleep 2
check "les deux sont en attente" "$(job_states)" "queued queued "
set_status home-main idle
wait_until 25 '[ "$(job_states)" = "sent sent " ]'
check "ordre d'arrivée conservé" "$(prompts_of home-main)" "idle|/clear
idle|Première
idle|/clear
idle|Seconde"
teardown_world

echo "un agent manquant est créé dans le tab 1 du workspace"
setup_world
enqueue w1 home-main '~' "Demande à froid"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "split du premier pane du tab 1, dans son cwd" "$(cat "$FAKE_HERDR_WORLD/splits")" "pane split w1:p1 --direction down --cwd /work/project --no-focus"
check "Claude en yolo avec le nom Remote Control home—main" "$(cat "$FAKE_HERDR_WORLD/starts")" "--kind claude --pane w1:p2 --timeout 60000 -- --dangerously-skip-permissions --remote-control home—main"
check "la demande part après /clear" "$(prompts_of home-main)" "idle|/clear
idle|Demande à froid"
teardown_world

echo "un agent du même nom dans un autre workspace n'est jamais visé"
setup_world
add_agent home-main w9 idle
enqueue w1 home-main '~' "Mauvaise cible"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "l'envoi échoue sans rien envoyer" "$(job_states)|$(prompts_of home-main)" "failed |"
teardown_world

echo "l'iPhone enregistre son token et installe le hook de notification"
setup_world
token="$(printf 'ab%.0s' $(seq 32))"
echo "// hook" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push "$token" sandbox com.skelz0r.heraldr.dev ABCDE12345
echo "// hook v2" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push "$token" sandbox com.skelz0r.heraldr.dev ABCDE12345
check "le token, l'environnement APNs, le topic et l'équipe sont retenus" "$(cat "$HERALDR_STATE_DIR/push-device.json")" "{\"token\":\"$token\",\"env\":\"sandbox\",\"topic\":\"com.skelz0r.heraldr.dev\",\"team\":\"ABCDE12345\"}"
check "le hook est toujours la version envoyée par l'app" "$(cat "$HERALDR_STATE_DIR/plugin/notify-hook.mjs")" "// hook v2"
check "le plugin herdr n'est lié qu'une fois" "$(cat "$FAKE_HERDR_WORLD/plugin_links")" "plugin link $HERALDR_STATE_DIR/plugin"
check "un token mal formé est refusé" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" register-push 'abc;rm' sandbox t ABCDE12345 2>&1; echo $?)" "invalid token
2"
teardown_world

if [ $failures -gt 0 ]; then
  echo "$failures échec(s)"
  exit 1
fi
echo "tous les cas passent"
