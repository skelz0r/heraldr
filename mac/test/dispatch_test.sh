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
  printf '%s' "$4" | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue "$1" "$2" "$(printf '%s' "$3" | base64)" > /dev/null
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
check "l'app lit le workspace, l'agent, l'état et la raison de l'échec" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2-)" "w1	home-main	failed	l'agent home-main appartient au workspace w9"
teardown_world

echo "un envoi vers le Claude d'un tab part tel quel, sans /clear ni consigne"
setup_world
add_agent wB:pG wB idle
enqueue_pane wB wB:pG keep "Le bouton est trop petit"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "le Claude du tab reçoit le texte brut, contexte gardé" "$(prompts_of wB:pG)" "idle|Le bouton est trop petit"
check "l'app retrouve l'envoi par son workspace et son pane" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2-4)" "wB	wB:pG	sent"
check "aucun Claude n'est lancé" "$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" ""
teardown_world

echo "un envoi vers un tab ne vide le contexte que si on le demande"
setup_world
add_agent wB:pG wB done
enqueue_pane wB wB:pG clear "Repars de zéro"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "/clear puis le texte brut" "$(prompts_of wB:pG)" "done|/clear
done|Repars de zéro"
teardown_world

echo "les envois vers un tab occupé ou bloqué attendent, dans l'ordre"
setup_world
add_agent wB:pG wB blocked
enqueue_pane wB wB:pG keep "Premier retour"
sleep 1.1
enqueue_pane wB wB:pG keep "Second retour"
sleep 2
check "rien n'est envoyé pendant qu'il attend une réponse" "$(prompts_of wB:pG)|$(job_states)" "|queued queued "
set_status wB:pG working
sleep 2
check "rien n'est envoyé pendant qu'il travaille" "$(prompts_of wB:pG)" ""
set_status wB:pG idle
wait_until 15 '[ "$(job_states)" = "sent sent " ]'
check "ordre d'arrivée conservé, jamais en working" "$(prompts_of wB:pG)" "idle|Premier retour
idle|Second retour"
teardown_world

echo "un pane d'un autre workspace ou sans Claude n'est jamais visé"
setup_world
add_agent w9:p3 w9 idle
add_agent wB:p7 wB idle
echo codex > "$FAKE_HERDR_WORLD/agents/wB:p7/kind"
enqueue_pane wB w9:p3 keep "Mauvais workspace"
enqueue_pane wB wB:pZ keep "Pane fermé"
enqueue_pane wB wB:p7 keep "Pas un Claude"
wait_until 10 '[ "$(job_states)" = "failed failed failed " ]'
check "rien n'est envoyé ni lancé" "$(prompts_of w9:p3)$(prompts_of wB:p7)$(cat "$FAKE_HERDR_WORLD/starts" 2>/dev/null)" ""
check "la raison de chaque échec" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f3,5 | sort)" "w9:p3	le pane w9:p3 appartient au workspace w9
wB:p7	plus de Claude dans le pane wB:p7
wB:pZ	plus de Claude dans le pane wB:pZ"
check "un pane mal formé ou une option inconnue sont refusés" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB 'wB:p1;rm' keep 2>&1; echo $?)|$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB wB:p1 maybe >/dev/null 2>&1; echo $?)" "invalid pane: wB:p1;rm
2|2"
teardown_world

echo "un pane dont le Claude est remplacé pendant l'attente ne reçoit rien"
setup_world
add_agent wB:pG wB working
enqueue_pane wB wB:pG keep "Pour l'ancien Claude"
sleep 2
echo codex > "$FAKE_HERDR_WORLD/agents/wB:pG/kind"
set_status wB:pG idle
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "l'envoi échoue sans rien envoyer au nouvel agent" "$(job_states)|$(prompts_of wB:pG)" "failed |"
teardown_world

echo "le pane d'un agent nommé n'est jamais visé comme un tab"
setup_world
add_agent wB:pG wB idle
echo acme-main > "$FAKE_HERDR_WORLD/agents/wB:pG/name"
enqueue_pane wB wB:pG keep "Contourne la file du main"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "l'envoi échoue sans rien envoyer, la file du main reste seule" "$(job_states)|$(prompts_of wB:pG)" "failed |"
check "la raison nomme l'agent" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5)" "le pane wB:pG est l'agent acme-main : vise-le par son nom"
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

echo "Home relaie une demande au -main du workspace du projet, avec la consigne standard"
setup_world
add_workspace w5 5 'Vidéo studio'
relay w5 "Ajoute un sous-titre"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "l'agent du projet est créé dans son workspace, nommé comme le fait l'app" "$(cat "$FAKE_HERDR_WORLD/starts")" "--kind claude --pane w5:p2 --timeout 60000 -- --dangerously-skip-permissions --remote-control Vidéo studio—main"
check "il reçoit /clear puis la demande enveloppée qui finit par /start" "$(prompts_of vid-o-studio-main)" "idle|/clear
idle|Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : attention aux erreurs de transcription).

Ajoute un sous-titre

Consignes :
- explore le code pour comprendre la demande, ne modifie rien ici
- si la demande est ambiguë, pose tes questions avec AskUserQuestion
- termine obligatoirement en dispatchant le travail avec /start"
check "l'envoi apparaît dans le workspace du projet" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2,3)" "w5	vid-o-studio-main"
teardown_world

echo "un relais vers Home ou un workspace inconnu est refusé"
setup_world
add_workspace w1 1 'Home'
relay w1 "Boucle"
check "relais vers Home, le workspace 1, refusé" "$?" "2"
relay w404 "Perdu"
check "relais vers un workspace inconnu refusé" "$?" "2"
check "aucun envoi créé" "$(job_states)" ""
teardown_world

echo "Home relaie au même agent que celui que l'app viserait pour ce workspace"
setup_world
number=2
while IFS="$(printf '\t')" read -r label agent; do
  add_workspace "w$number" "$number" "$label"
  relay "w$number" "Demande"
  check "$label → $agent" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | awk -F '\t' -v w="w$number" '$2 == w { print $3 }')" "$agent"
  number=$((number + 1))
done < "$here/agent-names.tsv"
teardown_world

echo "une capture envoyée par l'iPhone est gardée sur le Mac, lisible par son chemin"
setup_world
printf 'faux jpeg' > "$sandbox/capture.jpg"
path="$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg < "$sandbox/capture.jpg")"
check "le chemin rendu est absolu, sous le dossier d'état, avec l'extension" "$(printf '%s' "$path" | grep -Ec "^$HERALDR_STATE_DIR/attachments/[^/]+\.jpg$")" "1"
check "le fichier est l'image reçue, intacte" "$(cat "$path")" "faux jpeg"
check "une image vide ou une extension inconnue sont refusées" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg < /dev/null 2>&1; echo $?)|$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach 'sh;rm' 2>&1; echo $?)" "invalid attachment size: 0
2|invalid extension: sh;rm
2"
teardown_world

echo "une capture que le Mac n'a pas pu écrire n'est jamais annoncée comme posée"
setup_world
mkdir -p "$HERALDR_STATE_DIR/attachments"
chmod 500 "$HERALDR_STATE_DIR/attachments"
output="$(echo image | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach jpg 2>/dev/null)"
status=$?
chmod 700 "$HERALDR_STATE_DIR/attachments"
check "échec signalé à l'app, sans chemin" "$status|$output" "1|"
teardown_world

echo "une capture reste disponible une semaine, pour un envoi qui attend ou une session lancée par /start"
setup_world
recent="$(echo recent | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach png)"
old="$(echo old | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" attach png)"
touch -t "$(date -v-6d +%Y%m%d%H%M)" "$recent"
touch -t "$(date -v-8d +%Y%m%d%H%M)" "$old"
/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status > /dev/null
check "la capture de six jours est gardée, celle de huit jours supprimée" "$([ -f "$recent" ] && echo garde)|$([ -f "$old" ] && echo garde)" "garde|"
teardown_world

echo "le lexique de l'iPhone se sauvegarde sur le Mac et se relit tel quel"
setup_world
lexicon() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" "lexicon-$1"
}
check "sans sauvegarde, rien n'est lu et ce n'est pas une erreur" "$(lexicon get; echo "code $?")" "code 0"
cat > "$sandbox/lexique.json" <<'JSON'
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
lexicon put < "$sandbox/lexique.json"
check "l'écriture réussit" "$?" "0"
lexicon get > "$sandbox/relu.json"
check "relu octet pour octet" "$(cmp -s "$sandbox/lexique.json" "$sandbox/relu.json" && echo identique)" "identique"
check "rangé dans ~/.config/heraldr" "$(cmp -s "$sandbox/lexique.json" "$HERALDR_CONFIG_DIR/lexique.json" && echo identique)" "identique"
printf '{"version":1,"terms":[]}' | lexicon put
check "une nouvelle sauvegarde écrase la précédente" "$(lexicon get)" '{"version":1,"terms":[]}'
check "un envoi tronqué est refusé" "$(printf '{"version":1,"ter' | lexicon put 2>&1; echo "code $?")" "lexique illisible
code 2"
check "une version qui n'est pas un entier est refusée" "$(printf '{"version":"1","terms":[]}' | lexicon put 2>&1; echo "code $?")" "lexique illisible
code 2"
check "un envoi vide est refusé" "$(lexicon put < /dev/null 2>&1; echo "code $?")" "lexique illisible
code 2"
check "la sauvegarde précédente reste intacte, sans fichier temporaire" "$(lexicon get; ls "$HERALDR_CONFIG_DIR")" '{"version":1,"terms":[]}lexique.json'
teardown_world

if [ $failures -gt 0 ]; then
  echo "$failures échec(s)"
  exit 1
fi
echo "tous les cas passent"
