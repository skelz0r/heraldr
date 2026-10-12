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
check "l'app lit le workspace, l'agent, l'état et la raison de l'échec" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2-5)" "w1	home-main	failed	l'agent home-main appartient au workspace w9"
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
- si c'est une simple question, sans travail à faire : réponds sans /start avec \`/bin/sh \"\$HOME/.local/state/heraldr/dispatch.sh\" answer $(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f1)\`, sur l'entrée standard un résumé d'une phrase, une ligne vide puis la réponse complète en markdown
- sinon, termine obligatoirement en dispatchant le travail avec /start"
check "l'envoi apparaît dans le workspace du projet" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f2,3)" "w5	vid-o-studio-main"
teardown_world

echo "une réponse reste lisible une semaine, au-delà de l'heure des autres envois"
setup_world
add_agent home-main w1 idle
enqueue w1 home-main '~' "Comment marche le cache ?"
enqueue w1 home-main '~' "Corrige le cache"
wait_until 25 '[ "$(job_states)" = "sent sent " ]'
question="$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | head -1 | cut -f1)"
printf 'Vidé au déploiement.\n\nDétail.\n' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" answer "$question" 2>/dev/null
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$HERALDR_STATE_DIR"/jobs/*/state
check "après deux heures, seule la question répondue reste" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f1,4,6)" "$question	sent	answered"
touch -t "$(date -v-8d +%Y%m%d%H%M)" "$HERALDR_STATE_DIR/jobs/$question/answer"
check "après huit jours, elle disparaît aussi" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status)" ""
teardown_world

echo "un envoi ne part qu'une fois que Claude a commencé le précédent, jamais pendant son démarrage"
setup_world
add_agent home-main w1 idle
echo 3 > "$FAKE_HERDR_WORLD/agents/home-main/turn_seconds"
enqueue w1 home-main '~' "Première"
enqueue w1 home-main '~' "Seconde"
wait_until 40 '[ "$(job_states)" = "sent sent " ]'
check "le /clear de la seconde attend la fin du travail sur la première" "$(prompts_of home-main)" "idle|/clear
idle|Première
idle|/clear
idle|Seconde"
teardown_world

echo "un Claude que herdr met plus de 5 s à voir travailler ne reçoit pas le /clear suivant pendant son démarrage"
setup_world
export FAKE_HERDR_DETECTION_DELAY=7
add_agent home-main w1 idle
echo 2 > "$FAKE_HERDR_WORLD/agents/home-main/turn_seconds"
enqueue w1 home-main '~' "Lente"
enqueue w1 home-main '~' "Suivante"
wait_until 60 '[ "$(job_states)" = "sent sent " ]'
check "le /clear de la suivante attend la fin de la lente" "$(prompts_of home-main)" "idle|/clear
idle|Lente
idle|/clear
idle|Suivante"
unset FAKE_HERDR_DETECTION_DELAY
teardown_world

echo "six envois de la même seconde partent dans l'ordre d'arrivée"
setup_world
add_agent wB:pG wB working
echo 0.3 > "$FAKE_HERDR_WORLD/agents/wB:pG/turn_seconds"
for request in un deux trois quatre cinq six; do
  enqueue_pane wB wB:pG keep "$request"
done
set_status wB:pG idle
wait_until 40 '[ "$(job_states)" = "sent sent sent sent sent sent " ]'
check "les six sont partis" "$(job_states)" "sent sent sent sent sent sent "
check "ordre d'arrivée conservé" "$(prompts_of wB:pG | cut -d '|' -f2 | tr '\n' ' ')" "un deux trois quatre cinq six "
teardown_world

echo "un envoi attend le compteur tenu par un autre envoi, même avant que celui-ci ait noté son pid"
setup_world
mkdir -p "$HERALDR_STATE_DIR/locks/sequence"
printf 'x' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue-pane wB wB:pG keep > /dev/null 2>&1 &
sleep 1
check "aucun envoi créé tant que le compteur est pris" "$(job_states)" ""
rmdir "$HERALDR_STATE_DIR/locks/sequence"
wait_until 10 '[ -n "$(job_states)" ]'
check "l'envoi est créé dès que le compteur est rendu" "$(job_states | wc -w | tr -d ' ')" "1"
teardown_world

echo "un nom d'agent invalide ou une demande vide ne créent aucun envoi"
setup_world
check "nom d'agent hors convention herdr refusé" "$(echo x | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w1 'Home-Main' "$(printf '~' | base64)" 2>&1; echo $?)" "invalid agent name: Home-Main
2"
check "demande vide refusée" "$(printf '' | /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" enqueue w1 home-main "$(printf '~' | base64)" 2>&1; echo $?)" "empty prompt
2"
check "aucun envoi créé" "$(job_states)" ""
teardown_world

echo "un Claude qui ne démarre pas fait échouer l'envoi avec la raison de herdr"
setup_world
echo pane_not_ready > "$FAKE_HERDR_WORLD/start_error"
enqueue w1 home-main '~' "Demande à froid"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "échec annoncé avec la raison de herdr" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f4)|$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5 | grep -o 'agent start: .*pane_not_ready')" "failed|agent start: {\"error\":{\"code\":\"pane_not_ready"
teardown_world

echo "un /clear sans effet fait échouer l'envoi, sans envoyer la demande dans l'ancien contexte"
setup_world
export HERALDR_CLEAR_TIMEOUT_SECONDS=2
add_agent home-main w1 idle
touch "$FAKE_HERDR_WORLD/agents/home-main/ignores_clear"
enqueue w1 home-main '~' "Contexte propre exigé"
wait_until 10 '[ "$(job_states)" = "failed " ]'
check "seul le /clear est parti" "$(prompts_of home-main)" "idle|/clear"
check "la raison dit que le contexte n'a pas été vidé" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f5)" "/clear sans nouvelle session après 2s"
unset HERALDR_CLEAR_TIMEOUT_SECONDS
teardown_world

echo "la file d'un agent reprend après un runner mort qui tenait son verrou"
setup_world
add_agent home-main w1 idle
dead_pid="$(sh -c 'echo $$')"
mkdir -p "$HERALDR_STATE_DIR/locks/home-main"
echo "$dead_pid" > "$HERALDR_STATE_DIR/locks/home-main/pid"
enqueue w1 home-main '~' "Après le crash"
wait_until 15 '[ "$(job_states)" = "sent " ]'
check "la demande part" "$(prompts_of home-main | tail -n 1)" "idle|Après le crash"
teardown_world

echo "les envois partis sont oubliés après une heure, les échecs après un jour"
setup_world
add_agent wB:pG wB idle
echo 0.1 > "$FAKE_HERDR_WORLD/agents/wB:pG/turn_seconds"
for request in récent ancien; do enqueue_pane wB wB:pG keep "$request"; done
for request in récent ancien; do enqueue_pane wB wB:pZ keep "$request"; done
wait_until 20 '[ "$(job_states | tr " " "\n" | sort | tr "\n" " ")" = " failed failed sent sent " ]'
age_job() {
  for job in "$HERALDR_STATE_DIR"/jobs/*; do
    if [ "$(cat "$job/agent")" = "$1" ] && grep -qx "$2" "$job/prompt"; then
      touch -t "$(date -v-"$3" +%Y%m%d%H%M)" "$job/state"
    fi
  done
}
age_job wB:pG récent 59M
age_job wB:pG ancien 61M
age_job wB:pZ récent 23H
age_job wB:pZ ancien 25H
check "restent l'envoi de 59 min et l'échec de 23 h" "$(/bin/sh "$HERALDR_STATE_DIR/dispatch.sh" status | cut -f3,4 | sort | tr '\t\n' ' |')" "wB:pG sent|wB:pZ failed|"
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

echo "le journal des dictées s'ajoute sur le Mac, sans doublon ni entrée abîmée"
setup_world
journal_append() {
  /bin/sh "$HERALDR_STATE_DIR/dispatch.sh" journal-append
}
journal="$HERALDR_CONFIG_DIR/journal-dictees.jsonl"
first='{"id":"A1","salves":[{"edited":"Lance Acme.","proposed":"Lance Acme.","raw":"lance ack me"}],"sent":"Lance Acme.","version":1}'
second='{"id":"B2","salves":[],"sent":"Ouvre la PR.","version":1}'
check "sans journal, le premier envoi le crée" "$(printf '%s\n' "$first" | journal_append; echo "code $?"; cat "$journal")" "code 0
$first"
check "un envoi suivant s'ajoute à la fin, une entrée déjà reçue n'est pas doublée" "$(printf '%s\n%s\n' "$first" "$second" | journal_append; echo "code $?"; cat "$journal")" "code 0
$first
$second"
check "une entrée tronquée refuse tout l'envoi" "$(printf '%s\n{"id":"C3","version":1,"se\n' '{"id":"D4","version":1}' | journal_append 2>&1; echo "code $?")" "journal illisible
code 2"
check "une entrée sans version entière est refusée" "$(printf '{"id":"C3","version":"1"}\n' | journal_append 2>&1; echo "code $?")" "journal illisible
code 2"
check "une entrée sans id lisible est refusée" "$(printf '{"id":"a b","version":1}\n' | journal_append 2>&1; echo "code $?")" "journal illisible
code 2"
check "un envoi vide est refusé" "$(journal_append < /dev/null 2>&1; echo "code $?")" "journal illisible
code 2"
check "une entrée dont l'id porte un retour à la ligne est refusée" "$(printf '{"id":"A1\\n.*","version":1}\n' | journal_append 2>&1; echo "code $?")" "journal illisible
code 2"
check "une entrée qui n'est pas du JSON est refusée" "$(printf '<plist version="1.0"><dict><key>version</key><integer>1</integer><key>id</key><string>X1</string></dict></plist>\n' | journal_append 2>&1; echo "code $?")" "journal illisible
code 2"
check "le journal reste intact, sans fichier temporaire" "$(cat "$journal"; ls "$HERALDR_CONFIG_DIR")" "$first
$second
journal-dictees.jsonl"
printf '%s' "$first" > "$journal"
printf '%s\n' "$second" | journal_append
check "un journal sans retour final reste une ligne par entrée" "$(cat "$journal")" "$first
$second"
rm "$journal"
for n in 1 2 3 4 5 6 7 8; do
  printf '{"id":"P%s","version":1}\n' "$n" | journal_append &
done
wait
check "des ajouts simultanés gardent toutes les entrées" "$(sort "$journal" | tr -d '\n')" '{"id":"P1","version":1}{"id":"P2","version":1}{"id":"P3","version":1}{"id":"P4","version":1}{"id":"P5","version":1}{"id":"P6","version":1}{"id":"P7","version":1}{"id":"P8","version":1}'
teardown_world

if [ $failures -gt 0 ]; then
  echo "$failures échec(s)"
  exit 1
fi
echo "tous les cas passent"
