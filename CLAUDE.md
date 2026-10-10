# Heraldr

Télécommande de dispatch pour herdr : l'app iOS envoie une demande
(écrite, dictée ou collée) au Claude `<slug>-main` d'un workspace herdr
du Mac, par SSH, sans daemon côté Mac. Usage personnel, installée
directement sur l'iPhone.

- iOS : Swift 6 (concurrence stricte), SwiftUI, iOS 26, projet XcodeGen
- SSH : package HeelerSSH, submodule `Vendor/Heeler` épinglé
- Mac : `mac/dispatch.sh` (file d'envoi) et `mac/notify-hook.mjs`
  (plugin herdr qui pousse les questions vers APNs), embarqués dans
  l'app et réinstallés par elle à chaque usage

## Commandes

```sh
bin/setup-ios                # Xcode, XcodeGen, submodule Heeler
bin/generate-ios             # ios/project.yml -> .xcodeproj, patches Heeler
bin/build-ios [simulator|device]
bin/run-ios                  # simulateur
bin/run-ios-device [uuid]    # iPhone, signature par clé App Store Connect
bin/run-ios-tests [suite]    # tests de l'app (iPhone 17 Pro), puis bin/run-mac-tests
bin/run-mac-tests            # dispatch.sh (faux herdr) et hook (faux APNs), sans Xcode
bin/local-ci                 # tous les contrôles (iOS sauté si diff docs only)
bin/local-ci push            # contrôles puis push sans CI distante
```

Lancer les commandes longues avec un chemin absolu
(`$PWD/bin/local-ci push`, `$PWD/bin/run-ios-tests`) : plusieurs
worktrees tournent en parallèle et la ligne de commande doit dire de
quel worktree elle vient. Ne cibler un processus avec `pkill -f` que par
ce chemin absolu.

## Structure

```
ios/Heraldr/
├── App/        # HeraldrApp, AppModel (@Observable, état de l'écran)
├── Dispatch/   # AgentName (slug), PromptEnvelope (consignes), Dispatcher (exec dispatch.sh), SendHistory
├── Herdr/      # HerdrClient : API JSON sur herdr.sock, Workspace, Agent
├── Mac/        # MacLink (actor SSH, reconnexion), PairedMac
├── Pairing/    # PairingCode (HERDR-PAIR:1), PairingCeremony, DeviceKey (Keychain)
├── Push/       # PushDevice, QuestionNotification, AppDelegate
├── Voice/      # Dictation (SpeechAnalyzer), TranscriptCleaner (Foundation Models)
└── UI/
ios/HeraldrTests/   # Swift Testing
mac/                # dispatch.sh, notify-hook.mjs
mac/test/           # dispatch_test.sh + fake-herdr, notify_hook_test.mjs, agent-names.tsv
```

## Code

- Tout fichier ou cible passe par `ios/project.yml` ; ne jamais éditer
  le `.xcodeproj`, généré et ignoré
- Ne pas toucher `Vendor/Heeler` hors `Vendor/patches/`, appliqués par
  `bin/generate-ios`
- Pas de commentaires, des noms parlants ; fichiers terminés par un
  newline
- Textes affichés en français, tutoiement
- Le slug de l'agent et la consigne standard existent en Swift et dans
  `dispatch.sh` (relais de Home) : toute modification se fait des deux
  côtés, les tests de contrat le vérifient

## Tests

Quand écrire un test : politique globale (`~/.claude/CLAUDE.md`,
section Testing), sans exception. Zones de ce projet où un bug coûte
cher ou passe inaperçu, donc à couvrir :

- contrat app ↔ `dispatch.sh` : commandes, arguments, sortie tabulée de
  `status`, nom d'agent et consigne dupliqués (`docs/spec.md` §8.2)
- file d'envoi sur le Mac : jamais d'envoi pendant que l'agent
  travaille ou est bloqué, ordre conservé, `/clear` avant chaque
  demande, jamais un agent du même nom dans un autre workspace
- routage de Home : consigne de relais, refus de relayer vers Home
- appairage : code expiré ou sans amorçage, réponse d'enrôlement, clé
  hôte épinglée
- lecture tolérante de l'API herdr : champ ou état inconnu
- notifications : hook (debounce, une notif par question, `-main`
  seulement, token mort), payload lu par l'app, format du token
- vecteurs partagés : `pairing-code-v1.json` (plugin Heeler) et
  `mac/test/agent-names.tsv` (app et `dispatch.sh`)

Frontières à mocker, et rien d'autre :

- herdr : `mac/test/fake-herdr` dans le PATH, monde décrit en fichiers
- APNs : serveur HTTP/2 local (`HERALDR_APNS_ORIGIN`)
- SSH : pas de couture aujourd'hui, voir ci-dessous
- Keychain, UserDefaults, Foundation Models, Speech, caméra, horloge :
  injection (`now:` de `PairingCeremony.pair`)
- jamais un type de l'app (`Dispatcher`, `HerdrClient`, `AppModel`…)

Où placer un test :

- comportement du Mac : `mac/test/dispatch_test.sh` (bout en bout du
  script avec `fake-herdr`) ou `mac/test/notify_hook_test.mjs`
- app : `ios/HeraldrTests/`, Swift Testing, `@Suite` et `@Test` décrits
  par une phrase métier en français ; tests hébergés dans l'app, donc
  `Bundle.main` est celui de l'app (scripts embarqués)
- un contrat partagé entre deux côtés passe par un fichier de vecteurs
  lu par les deux, déclaré en ressource de `HeraldrTests` dans
  `project.yml`

Pas de test aujourd'hui pour `AppModel` (choix de la notice, échec
annoncé, état de la cible) ni pour l'exec SSH : `AppModel` crée
lui-même `MacLink` et lit des stores statiques. Les garanties qui
coûtent cher (file, workspace, ordre) sont tenues par `dispatch.sh` et
testées là. Introduire un protocole de transport sous `MacLink` le jour
où un bug de ce côté passe inaperçu, pas avant.

Pas de tests UI (XCUITest) : sans couture SSH, l'app ne dépasse pas
l'écran d'appairage en simulateur. Le jour où il en faut, ajouter une
cible `HeraldrUITests` dans `project.yml`, cibler les éléments par
`accessibilityIdentifier` (jamais par libellé), garder la capture avec
`XCTAttachment(screenshot:)` en `.keepAlways`, l'exporter du
`.xcresult` et la regarder ; captures livrables dans
`~/share/screenshots/`.

Un test qui casse sans changement de comportement voulu : dire si
c'est le test ou le code qui a tort, ne jamais l'adapter en silence.

Fin d'itération : `$PWD/bin/run-ios-tests` (ou `bin/run-mac-tests` si
seuls les scripts Mac ont changé), puis `docs/spec.md` à jour.

Plusieurs worktrees qui lancent leurs tests en même temps sur le même
simulateur se font planter : passer un autre simulateur avec
`IOS_TEST_SIMULATOR_NAME`.

## Spécification

**IMPORTANT** : `docs/spec.md` décrit ce que fait l'app, écran par
écran, et son contrat avec le Mac. Elle est normative : un écart entre
la spec et le code se résout en faveur de la spec.

Tout changement de comportement de l'app (`ios/Heraldr`) ou des
scripts Mac (`mac/dispatch.sh`, `mac/notify-hook.mjs`) DOIT mettre à
jour la spec dans le même commit ou la même PR : écran, état, règle,
texte affiché, commande ou sortie de `dispatch.sh`, payload, tolérance
à un champ inconnu. Un bug découvert sans correction immédiate va dans
*Écarts connus* sous un nouvel identifiant `E<n>` ; sa correction l'en
retire.

`bin/local-ci` avertit (sans bloquer) quand ces chemins ont changé
depuis `origin/main` sans la spec. Un refactoring sans effet visible
n'appelle pas de mise à jour : le dire dans la PR.

Le comment va dans `docs/architecture.md`, le pourquoi et les options
écartées dans `docs/decisions.md`.

## QA manuelle

`QA.md` : smoke test sur le vrai iPhone pour ce que l'automatique ne
voit pas (SSH réel, herdr, dictée, Apple Intelligence, push, lien vers
l'app Claude). Le faire évoluer seulement quand un parcours critique
change.

## Git

- Commits, PR, docs et descriptions de tests en français
- Pousser une branche avec `$PWD/bin/local-ci push` plutôt que
  `git push` : il valide le HEAD exact, pousse avec lease vers la
  branche du même nom et pose le statut « Local CI » ; jamais sur
  `main`
- `bin/local-ci` saute les tests iOS quand tout le diff depuis le
  merge-base avec `origin/main` est de la doc (`docs/`, `.claude/`,
  `*.md` hors `ios/` et `mac/`) ; un worktree sale ou un diff vide
  lancent tout

### Worktrees

Chaque sujet part dans un worktree dédié (skill `start`), sous
`worktrees/` (ignoré) :

```sh
git worktree add worktrees/<nom> -b feature/<nom> origin/main
```

Pas de script de setup : `bin/generate-ios` initialise le submodule
Heeler au premier build. Après merge :
`git worktree remove worktrees/<nom> && git branch -d feature/<nom>`.

## Documentation

- `docs/spec.md` : comportement normatif de l'app et contrat avec le Mac
- `docs/architecture.md` : SSH, dispatch, file, notifications
- `docs/decisions.md` : journal des décisions
- `docs/toolchain.md` : scripts, signature, écarts avec Heeler
- `docs/risks.md` : spikes et points vérifiés
- `docs/roadmap.md`, `docs/vision.md`, `docs/design.md`
- `QA.md` : smoke test sur l'iPhone
