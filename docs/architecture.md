# Architecture

## Vue d'ensemble

```text
iPhone ──SSH (LAN ou Tailscale)──> sshd du Mac
                                    ├─ direct-streamlocal → herdr.sock (API JSON)
                                    └─ exec → script de dispatch détaché (file)
```

Aucun daemon ni port supplémentaire sur le Mac. Même approche que Heeler
(ADR 0011 de Heeler : libssh2 `direct-streamlocal`).

## Côté Mac

Prérequis déjà en place :

- Remote Login (sshd) actif, port 22
- Tailscale SSH désactivé (`RunSSH: false`), indispensable car le pairing
  Heeler repose sur une `command=` forcée d'OpenSSH
- plugin `heeler` installé et activé
- herdr 0.9.3

Rien d'autre à installer pour le MVP. Les notifications (V2) ajoutent
un prérequis :

- Node dans le PATH de herdr (déjà requis par le plugin Heeler)
- la clé APNs `.p8` de l'équipe `ABCDE12345`, copiée telle que la
  télécharge Apple dans `~/.config/heraldr/AuthKey_<KEYID>.p8`
  (mode 600) : le key id vient du nom du fichier. Aujourd'hui celle de
  local_events, `KEYID67890` ; une clé APNs vaut pour toutes les apps
  de l'équipe

Le reste vient de l'app : bundle id (`com.skelz0r.heraldr.dev`),
équipe, environnement APNs (sandbox en Debug, production sinon) et le
plugin herdr lui-même.

## Pairing

Réutilisation telle quelle du format `HERDR-PAIR:1` du plugin Heeler
(`plugin/README.md`, section « Pairing Code envelope (v1) », vecteurs de
test dans `plugin/test-vectors/pairing-code-v1.json`) :

1. sur le Mac : `herdr plugin action invoke heeler.pair`, popup avec QR
2. le QR contient `HERDR-PAIR:1:<base64url(JSON)>` : `addrs`, `port`,
   `user`, `fp` (empreinte SHA256 de la clé hôte, épinglée), `seed`
   (clé Ed25519 bootstrap, usage unique, 2 min), `exp`
3. l'app génère sa Device Key Ed25519 (privée dans le Keychain), se
   connecte avec la clé bootstrap, écrit sa clé publique sur stdin
4. réponse `HERDR-ENROLL:OK:<fp>`, la clé bootstrap est retirée
5. l'app retient l'adresse qui a répondu, et essaie les autres en cas
   d'échec (LAN puis Tailscale)

Les vecteurs de test Heeler deviennent des tests du parseur côté app
(contrat public consommé).

## SSH côté iOS

Package `HeelerSSH` (libssh2 + OpenSSL, Apache-2.0). Il vit dans un
sous-dossier du dépôt Heeler (`Packages/HeelerSSH`, binaires
xcframework de 20 Mo) : SPM ne peut pas le référencer directement. On
ajoute Heeler en submodule git `Vendor/Heeler`, épinglé sur un commit, et
XcodeGen déclare le package local
`Vendor/Heeler/Packages/HeelerSSH`. Utilisé pour :

- `direct-streamlocal` vers `herdr.sock` : requêtes JSON de l'API herdr
  (lecture : `workspace.list`, `tab.list`, `agent.list`)
- `exec` : lancement du script de dispatch

Chemin du socket : `~/.config/herdr/herdr.sock` (à confirmer via la
session herdr par défaut).

## Dispatch

L'app embarque un script shell versionné (`mac/dispatch.sh`). Chaque
envoi fait deux exec SSH :

1. `install` : le script est écrit sur stdin dans
   `~/.local/state/heraldr/dispatch.sh` (toujours la version de
   l'app installée)
2. `enqueue <workspace_id> <agent> <label_base64>` : le prompt enveloppé
   arrive brut sur stdin et devient un job
   `~/.local/state/heraldr/jobs/<horodatage>-<séquence>-<aléa>/`, puis le
   script lance son runner détaché :
   `nohup /bin/sh dispatch.sh run <agent> </dev/null >/dev/null 2>&1 &`

Un job est un dossier de fichiers texte : `workspace_id`, `agent`,
`label`, `clear`, `prompt`, `state` (`queued`, `sending`, `sent`, `failed`) et
`error`. `dispatch.sh status` les liste en lignes tabulées pour l'app.

Le runner, détaché, survit à la mise en veille du téléphone (spike 7).
Il fixe son PATH (`/opt/homebrew/bin` absent en exec SSH), prend le
verrou de l'agent (`mkdir` atomique, pid dedans pour reprendre un verrou
mort) et traite les jobs de l'agent dans l'ordre de leur nom :
l'horodatage à la seconde, puis un compteur sur 12 chiffres tenu sous
un verrou `sequence` (un `mkdir` qui n'est jamais volé tant qu'il a
moins d'une minute, même sans pid écrit), qui départage deux envois de
la même seconde
(le pid qu'il remplace se comparait comme du texte, `10000` avant
`9999`, et repart de zéro après 99999) :

1. résout le tab 1 du workspace (`herdr tab list --workspace`, numéro 1)
2. cherche l'agent `<agent>` (`herdr agent get`)
3. s'il manque : `herdr pane split` du premier pane du tab 1, avec le
   cwd de ce pane, puis
   `herdr agent start <agent> --kind claude --pane <pane> --
   --dangerously-skip-permissions --remote-control "<label>—main"`
   (équivalent de `dclaude`, en gardant la détection de readiness herdr)
4. `herdr agent wait <agent> --until idle --until done`, sans timeout :
   c'est la file, qui attend aussi longtemps que l'agent travaille ou
   est bloqué
5. `herdr agent prompt <agent> "/clear"` sans `--wait` (spike 1 :
   `--wait` échoue en `agent_prompt_stalled`), puis attente du
   changement de `agent_session.value`
6. `herdr agent prompt <agent> "<prompt enveloppé>" --wait --until
   working --until blocked` : rend la main dès que herdr voit Claude
   travailler, sans attendre la fin. Sans cette attente, herdr montre
   encore l'agent `idle` le temps de détecter le nouveau tour, et le
   job suivant passait son `agent wait` puis envoyait son `/clear`
   pendant que Claude démarrait le précédent. Un `agent_prompt_stalled`
   (rien vu en 5 s, comme pour `/clear`) compte comme envoyé, le texte
   est parti, mais le runner attend encore jusqu'à 30 s (`agent wait
   --until working --until blocked`) que herdr voie Claude travailler :
   un démarrage lent n'est pas vidé par le `/clear` suivant. Un tour
   assez court pour finir avant d'être vu coûte ces 30 s au job suivant
7. `state` passe à `sent`, ou `failed` avec l'erreur ; les jobs `sent`
   sont supprimés après une heure, les `failed` après un jour

Un second envoi vers un agent occupé ne lance pas de deuxième runner :
le verrou est pris, son job attend que le runner en place le traite.
Les envois partent donc dans l'ordre, chacun précédé de son `/clear`.

`enqueue-pane <workspace_id> <pane_id> <clear|keep>` vise le Claude
d'un tab de worktree, que l'app désigne par son `pane_id` (premier
Claude du tab dans `agent.list`) : le prompt arrive sur stdin tel que
l'app l'a préparé (avertissement de dictée, sans consigne) et part
tel quel. Le job garde le `pane_id` dans `agent`, et `clear` dans un
fichier du même nom (absent des jobs d'un script plus ancien : `/clear`
fait). La file, l'attente `idle`/`done` et l'ordre sont ceux d'un
agent nommé, `herdr agent get|wait|prompt` acceptant un `pane_id`
comme cible ; le verrou remplace `:` par `@`, absent des noms d'agent.
Le runner ne crée jamais d'agent pour un pane : il échoue si le pane
n'héberge plus de Claude (`agent` différent de `claude`), s'il est
dans un autre workspace ou si son Claude porte un nom herdr (un
`-main` a sa propre file, clé par nom : deux verrous pour le même
Claude laisseraient passer deux envois à la fois). Il refait ces
vérifications après `agent wait`, juste avant d'envoyer, le pane
pouvant changer d'occupant pendant l'attente, puis n'envoie `/clear`
que pour `clear`.

`relay <workspace_id>` sert à l'agent de Home pour transmettre une
demande au projet qu'elle vise : la demande brute arrive sur stdin, le
script lit le label avec `herdr workspace get`, en déduit
`<slug>-main`, l'enveloppe dans la consigne standard et crée un job
comme `enqueue`. Il refuse Home (workspace numéro 1) comme cible. Le
slug et la consigne standard existent donc en double, dans
`AgentName.swift` / `PromptEnvelope.swift` et dans `dispatch.sh`, à
garder alignés. Le script est toujours installé sur le Mac au moment du
relais, puisque l'envoi vers Home vient de l'installer.

`attach <jpg|png>` reçoit une capture jointe à une demande : l'image
arrive brute sur stdin, est écrite dans
`~/.local/state/heraldr/attachments/<horodatage>-<id>.<ext>` (via un
`.tmp` renommé) et le script répond son chemin absolu. L'app fait un
`attach` par image avant l'`enqueue`, puis cite les chemins dans la
demande : Claude Code lit une image par son chemin avec Read, il n'y a
ni SFTP ni pièce jointe côté herdr. Les images ne sont pas rattachées
au job : `prune_jobs` (appelé par `run` et `status`) efface celles de
plus d'une semaine, assez pour un envoi resté en file ou une session
lancée plus tard par /start.

## Sauvegarde du lexique de dictée

```text
iPhone (dictation-lexicon.json) ──exec dispatch.sh lexicon-put──> ~/.config/heraldr/lexique.json
                                <──exec dispatch.sh lexicon-get── (après un appairage, lexique vide)
```

`LexiconKeeper` (module `Voice`) tient le lexique pour toute l'app :
`AppModel.lexicon` le lit et le modifie, l'aperçu et les Réglages
passent par lui. Chaque changement est écrit dans le fichier local et
lève `lexicon-backup-needed` (UserDefaults) ; `sync` écrit le lexique
entier sur le Mac et ne baisse le drapeau que si rien n'a changé
pendant l'écriture. `AppModel` lance `sync` 2 s après un changement et
après chaque rafraîchissement réussi, sur le `MacLink` déjà ouvert,
via `Dispatcher.lexiconMirror` (`install` puis `lexicon-get` ou
`lexicon-put`).

`pair` appelle `paired()` : lexique vide, `lexicon-restore-pending`
est levé et `sync` lit le Mac avant toute écriture ; sinon le prochain
`sync` écrase le Mac. Le drapeau survit à une relance, pour qu'une
lecture ratée ne laisse jamais une écriture écraser la sauvegarde.
`LexiconMirror` (deux closures) est la couture des tests, qui simulent
le Mac sans SSH.

## Journal des dictées

```text
ComposeView.send ──record──> dictation-journal.jsonl (en attente, iPhone)
                                 │ exec dispatch.sh journal-append
                                 v
                  ~/.config/heraldr/journal-dictees.jsonl (Mac, ajout seul)
```

`TranscriptCleaner.clean` rend, avec la salve, une `CleaningTrace` :
texte après le premier remplacement, remplacements faits par
`DictationLexicon.replacements(in:)` avant et après le modèle, indices
donnés et suivis ou non, jugé sur la réponse du modèle avant le second
remplacement (seul moment où elle existe). `DictatedText` garde les
salves et leurs révisions ; à l'envoi réussi, `AppModel.recordDictation`
en fait une `DictationJournalEntry` (rien pour Écrire ou Coller) que
`DictationJournal` ajoute à son fichier d'attente, puis l'envoie.
`upload` pousse toutes les lignes en attente en un seul
`journal-append` et ne retire que celles parties, une ligne ajoutée
pendant l'envoi restant pour le suivant ; il est rappelé à chaque
rafraîchissement réussi. `DictationJournalMirror` (une closure) est la
couture des tests. Une coupure après l'écriture sur le Mac fait
renvoyer l'entrée : `dispatch.sh` l'ignore grâce à son `id`.

Lire les chiffres : le journal est fait pour être analysé par un
Claude sur le Mac, une ligne par envoi, en ignorant les versions
supérieures à 1 et en dédoublonnant par `id` par prudence. Pour chaque
salve, la comparaison qui compte est `previewed` → `edited`, mot à
mot comme l'apprentissage (casse, accents et ponctuation en bord de
mot ignorés) :

- part des mots retouchés : mots changés de `previewed` sur ses mots,
  par semaine ; doit baisser si le lexique aide
- remplacement défait : un terme de `replacements` présent moins de
  fois dans `edited` que dans `previewed`, ou remplacé par l'entendu ;
  à rapporter par paire entendu → terme pour repérer les faux
  positifs, notamment les variantes de deux mots apprises avec un mot
  voisin
- indice suivi : `applied` des `hints` ; un indice suivi puis défait
  dans `edited` est un faux positif du modèle
- la sortie du modèle avant le second remplacement n'est pas gardée :
  `proposed` comparé à `replaced` montre le nettoyage et le second
  remplacement ensemble

## Notifications

```text
herdr ──pane.agent_status_changed──> plugin heraldr (node notify-hook.mjs)
                                      └─ HTTP/2 + JWT ES256 → APNs → iPhone
```

Enregistrement : au premier rafraîchissement réussi de chaque
lancement, l'app (autorisation accordée) fait un exec SSH
`dispatch.sh register-push <token> <sandbox|production> <topic>
<team_id>`, avec `mac/notify-hook.mjs` sur stdin. Le script :

1. écrit le hook et un manifeste `herdr-plugin.toml` dans
   `~/.local/state/heraldr/plugin/` (toujours la version de l'app)
2. le lie une fois avec `herdr plugin link`, s'il n'est pas déjà dans
   `herdr plugin list`
3. retient l'appareil dans `~/.local/state/heraldr/push-device.json`
   (un seul iPhone)

Le hook, un process court par changement d'état lancé par herdr :

1. ne fait rien si l'état reçu ne change pas le marqueur du pane
   (`~/.local/state/heraldr/notified/<pane>`) : `blocked` déjà notifié,
   ou autre état sans notif en cours
2. debounce de 3 s, puis `herdr agent get <pane>` : l'état doit tenir,
   sinon un événement plus récent s'en charge. Un état autre que
   `blocked` qui tient efface le marqueur et réarme le pane
3. ignore tout agent dont le nom ne finit pas par `-main`
4. URL de session : `~/.claude/sessions/*.json` dont le `sessionId` est
   `agent_session.value`, `https://claude.ai/code/<bridgeSessionId>`
5. question : lue à l'écran (`herdr pane read <pane> --source
   recent-unwrapped`), dans la boîte entre le dernier filet `─` et
   l'option sélectionnée `❯ 1.`. Lignes `│` : texte de
   l'AskUserQuestion. Sinon titre de la demande de permission
   (`Bash command` : description avant le premier filet `╌`) ou ligne
   `Do you want to …` (fichier édité, écrasé ou créé). Pas le
   transcript : Claude Code n'y écrit le `tool_use` en attente qu'une
   fois la réponse donnée, le dernier `tool_use` lisible est celui de
   l'outil déjà lancé avant
6. JWT ES256 signé avec la `.p8`, POST
   `/3/device/<token>` sur `api.sandbox.push.apple.com` ou
   `api.push.apple.com`, `apns-collapse-id` = nom de l'agent
7. 200 : marqueur posé. 410 ou `BadDeviceToken` : l'appareil est oublié
   jusqu'au prochain lancement de l'app. Les erreurs sortent sur stderr,
   lisibles par `herdr plugin log list --plugin heraldr`

Payload : `aps.alert` (titre = label du workspace, sous-titre = agent,
corps = question), `workspace_id`, `agent`, `session_url`. Au tap,
l'app cible le workspace, ouvre `session_url` en
`universalLinksOnly`, et affiche une carte « Ouvrir dans Claude » si
l'ouverture échoue ou que l'URL manque.

### Réponses

```text
Claude -main ──dispatch.sh answer <job_id>──> jobs/<job_id>/answer
                └─ node plugin/notify-hook.mjs answer <job_id> → APNs → iPhone
iPhone ──SSH read-answer <job_id>──> réponse complète (tap ou rafraîchissement)
```

`create_job` remplace `{{job_id}}` dans le prompt par l'id du job : la
consigne donne ainsi à Claude la commande exacte pour répondre. Le hook,
lancé en mode `answer`, lit `agent`, `workspace_id`, `label` et la
première ligne de `answer` dans le dossier du job, et poste avec
`apns-collapse-id` = id du job ; même gestion du token mort. `status`
ajoute la colonne `answered` : l'app récupère par `read-answer` toute
réponse d'un envoi qu'elle suit et n'a pas encore, notif ratée ou non.
Un job `sent` répondu échappe à la purge d'une heure et part sept jours
après sa réponse.

## App iOS

- Swift 6, SwiftUI, iOS 26 minimum (Liquid Glass, SpeechAnalyzer,
  Foundation Models)
- modules :
  - `Pairing` : scan QR (VisionKit DataScanner), parsing `HERDR-PAIR:1`,
    enrôlement, Keychain
  - `HerdrClient` : requêtes JSON sur streamlocal, modèles Codable
  - `Dispatch` : enveloppe du prompt, slug, exec du script, captures
    jointes (réduites et converties en JPEG sur l'iPhone, posées par
    `attach`), historique des 20 derniers envois (UserDefaults)
  - `Voice` : SpeechAnalyzer + nettoyage Foundation Models, lexique
    de dictée en termes et variantes (fichier JSON dans Application
    Support, `DictationLexiconStore`) ; le vocabulaire passe
    par `AnalysisContext.contextualStrings`, que seul
    `DictationTranscriber` exploite aujourd'hui, pas
    `SpeechTranscriber` : il reste fourni aux deux. Les variantes
    sûres sont remplacées par le code autour du nettoyage
    (`DictationLexicon.replacingKnownVariants`), le modèle passant par
    `CleaningModel`, injectable dans les tests
  - `Push` : autorisation, token APNs, tap sur les notifications
  - `UI` : liste, boutons, aperçu
- Foundation Models indisponible (Apple Intelligence off, modèle pas
  prêt) : on garde la transcription brute et on le signale dans l'aperçu
