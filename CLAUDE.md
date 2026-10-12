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
bin/setup-ios                # Xcode, XcodeGen, submodule Heeler, outils de lint épinglés
bin/generate-ios             # ios/project.yml -> .xcodeproj, patches Heeler
bin/build-ios [simulator|device]
bin/run-ios                  # simulateur
bin/run-ios-device [uuid]    # iPhone, signature par clé App Store Connect, install OTA hors LAN
bin/run-ios-tests [suite]    # tests unitaires de l'app, puis bin/run-mac-tests ; échoue si 0 test ou sous le plancher
bin/run-mac-tests            # dispatch.sh (faux herdr) et hook (faux APNs), sans Xcode
bin/lint                     # shellcheck, swift-format, SwiftLint, Biome, garde-fous (2 s)
bin/qa [--all|<classe>...]   # tests UI touchés par le diff sur le faux Mac, captures clair et sombre
bin/local-ci                 # lint puis tests (iOS sauté si diff docs only)
bin/local-ci push            # contrôles puis push sans CI distante
```

L'install sur l'iPhone suit le skill global `ios-device-install`
(`devicectl` sur le LAN, OTA via Tailscale ailleurs) : en OTA,
`bin/run-ios-device` affiche l'URL à ouvrir dans Safari sur l'iPhone.

Lancer les commandes longues avec un chemin absolu
(`$PWD/bin/local-ci push`, `$PWD/bin/run-ios-tests`) : plusieurs
worktrees tournent en parallèle et la ligne de commande doit dire de
quel worktree elle vient. Ne cibler un processus avec `pkill -f` que par
ce chemin absolu.

## Structure

```
ios/Heraldr/
├── App/        # HeraldrApp, AppModel (@Observable, état de l'écran), AppEnvironment (injection)
├── Debug/      # FakeMac et ses scénarios (#if DEBUG) : tests d'AppModel, tests UI, QA
├── Dispatch/   # AgentName (slug), PromptEnvelope (consignes), Dispatcher (exec dispatch.sh), SendHistory
├── Herdr/      # HerdrClient : API JSON sur herdr.sock, Workspace, Agent
├── Mac/        # MacTransport (protocole), MacLink (actor SSH, reconnexion), PairedMac
├── Pairing/    # PairingCode (HERDR-PAIR:1), PairingCeremony, DeviceKey (Keychain)
├── Push/       # PushDevice, QuestionNotification, AppDelegate
├── Voice/      # Dictation (SpeechAnalyzer), TranscriptCleaner (Foundation Models), DictationLexicon, LexiconKeeper (sauvegarde sur le Mac)
└── UI/
ios/HeraldrTests/   # Swift Testing
ios/HeraldrUITests/ # XCUITest sur le faux Mac, une classe par parcours
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
- Toute UI vise un rendu soigné et minimaliste, en Liquid Glass natif
  d'iOS 26 (`glassEffect`, styles `.glass`) : peu d'éléments, pas de
  capsule teintée, d'icône ni de couleur qui ne porte pas
  d'information ; vérifier le rendu en clair et en sombre
  (`docs/design.md`)
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
- SSH et Mac : `FakeMac` (`ios/Heraldr/Debug/`), conforme à
  `MacTransport`, scénario décrit en données (`FakeMacScenario`) ;
  `AppModel(environment: .fake(scenario, mac:, suiteName:))`
- SSH réel : seul le test de clé hôte épinglée vise le sshd du Mac
  (`127.0.0.1:22`, Remote Login, prérequis du projet) et s'arrête
  avant toute authentification
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

`AppModel` se teste par sa surface publique (`refresh`, `send`,
`resend`, `open`, `targetState`…) contre `FakeMac`
(`ios/HeraldrTests/AppModelTests.swift`) : notice, échec annoncé,
cible, rafraîchissement. `FakeMac` est un double de la frontière, à
faire évoluer comme `dispatch.sh` et herdr quand ils changent : il ne
doit jamais accepter ce que le vrai refuse. Les garanties de la file
(workspace, ordre, attente) restent tenues et testées par
`dispatch.sh`.

Tests UI (`ios/HeraldrUITests/`, XCUITest) : l'app tourne sur le faux
Mac (`launch("<preset>")` ou un scénario JSON dans
`HERALDR_FAKE_MAC`), les éléments sont visés par
`accessibilityIdentifier` (jamais par libellé ; tout élément qu'un test
vise en reçoit un), et `capture("<écran>", in: app)` garde l'écran en
clair et en sombre. Un parcours nouveau ou modifié a son test UI ; un
nouvel état à montrer a son preset dans `FakeMacScenario`. Jamais de
patch temporaire de fausses données.

Un test qui casse sans changement de comportement voulu : dire si
c'est le test ou le code qui a tort, ne jamais l'adapter en silence.

Fin d'itération : `$PWD/bin/run-ios-tests` (ou `bin/run-mac-tests` si
seuls les scripts Mac ont changé), `$PWD/bin/qa` si l'UI ou l'app ont
changé (voir *QA*), puis `docs/spec.md` à jour. Le lint tourne seul :
le hook Stop du projet (`.claude/settings.json`) lance `bin/lint` avant
de rendre la main, et `bin/local-ci` aussi.

Plusieurs worktrees qui lancent leurs tests en même temps sur le même
simulateur se font planter : `bin/qa` crée et vise par son udid un
simulateur propre au worktree (« Heraldr <worktree> »), à passer aussi
à `bin/run-ios-tests` avec `IOS_TEST_SIMULATOR_NAME`. Jamais `booted`.

## Spécification

**IMPORTANT** : `docs/spec.md` décrit ce que fait l'app, écran par
écran, et son contrat avec le Mac. Elle est normative : un écart entre
la spec et le code se résout en faveur de la spec.

Tout changement de comportement de l'app (`ios/Heraldr`) ou des
scripts Mac (`mac/dispatch.sh`, `mac/notify-hook.mjs`) DOIT mettre à
jour la spec dans le même commit ou la même PR : écran, état, règle,
texte affiché, commande ou sortie de `dispatch.sh`, payload, tolérance
à un champ inconnu. Aucun écart entre la spec et le code : un bug
découvert se corrige dans la branche, avec son test ; s'il ne peut
vraiment pas l'être tout de suite, la spec décrit le comportement réel.
`bin/lint` échoue si une section « Écarts connus » réapparaît avec du
contenu.

`bin/local-ci` avertit (sans bloquer) quand ces chemins ont changé
depuis `origin/main` sans la spec. Un refactoring sans effet visible
n'appelle pas de mise à jour : le dire dans la PR.

Le comment va dans `docs/architecture.md`, le pourquoi et les options
écartées dans `docs/decisions.md`.

## QA

La QA est faite par l'agent, en deux temps :

1. Fin d'itération, au simulateur : `$PWD/bin/qa` joue les classes de
   tests UI touchées par le diff (quelques minutes, `--all` pour tout,
   3 à 4 min, sur 3 clones du simulateur) et exporte les captures dans
   `~/share/screenshots/<worktree>/`. Les regarder, en clair et en
   sombre (`docs/design.md`), avant de dire que l'UI est faite ; un
   défaut vu se corrige avec son test.
2. Après un `bin/run-ios-device`, seulement si le diff touche l'une de
   ses zones : présenter à l'utilisateur 3 à 5 cases de `QA.md` au
   plus, celles de ces zones, jamais la liste entière. `QA.md` ne garde
   que ce qui exige le vrai iPhone et le vrai Mac ; une case qu'un test
   peut couvrir en sort.

## Git

- Commits, PR, docs et descriptions de tests en français
- Pousser une branche avec `$PWD/bin/local-ci push` plutôt que
  `git push` : il pousse le HEAD avec lease vers la branche du même
  nom, pose le statut « Local CI » en pending, lance les contrôles
  puis le passe en success, failure (étape qui a cassé) ou error
  (interruption) ; jamais sur `main`
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
- `QA.md` : ce qui exige le vrai iPhone et le vrai Mac, 3 à 5 cases par itération
