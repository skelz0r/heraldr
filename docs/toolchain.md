# Toolchain

Inspirée de `local_events/bin/*-ios`, avec XcodeGen en plus.

## Projet

- `ios/project.yml` (XcodeGen) versionné, `.xcodeproj` généré et ignoré
  par git : pas de conflits de `.pbxproj` entre worktrees d'agents
- bundle id de dev : `com.skelz0r.<nom>.dev`
- signature automatique avec l'équipe perso, installation directe sur
  l'iPhone (pas de TestFlight)

## Scripts

| Script | Rôle |
| --- | --- |
| `bin/setup-ios` | vérifie Xcode 26, xcode-select, XcodeGen, installe et vérifie les outils épinglés (shellcheck 0.11.0, SwiftLint 0.65.1, Biome 2.5.15, xcbeautify 3.2.1, AXe 1.8.0 ; swift-format vient d'Xcode), initialise le submodule Heeler |
| `bin/generate-ios` | `xcodegen generate`, applique `Vendor/patches/*.patch` au submodule |
| `bin/build-ios [simulator\|device]` | build |
| `bin/run-ios` | build et lancement simulateur |
| `bin/run-ios-device [uuid]` | build puis install sur l'iPhone par le skill global `ios-device-install` : `devicectl` si l'iPhone est joignable, sinon page d'install OTA via Tailscale (attente device busy, déverrouillage keychain CI comme local_events) |
| `bin/run-ios-tests [suite]` | tests unitaires en simulateur (`IOS_TEST_SIMULATOR_NAME`, iPhone 17 Pro par défaut), sortie complète par xcbeautify, warnings compris, puis `bin/run-mac-tests` ; lit le `.xcresult` et échoue si aucun test n'a tourné ou, suite complète, sous le plancher de `ios/minimum-test-count` (à relever avec les tests ajoutés). Les tests UI n'y tournent pas |
| `bin/lint` | shellcheck (`.shellcheckrc`), `xcrun swift-format lint --strict` (`.swift-format`), SwiftLint en CLI (`.swiftlint.yml`), Biome (`biome.json`), et deux garde-fous : `agent_status` lu seulement pour un agent, pas de section « Écarts connus » remplie dans la spec ; 2 s |
| `bin/qa [--all\|<classe>...]` | joue les classes de `HeraldrUITests` touchées par le diff depuis `origin/main` sur le simulateur « Heraldr <worktree> » (créé au besoin, visé par udid, barre d'état figée à 9:41), contre le faux Mac, et exporte les captures clair et sombre dans `~/share/screenshots/<worktree>/`, sur 3 clones en parallèle (`QA_WORKERS`) ; 3 à 4 min pour `--all` |
| `bin/run-mac-tests` | tests du script de dispatch (`mac/test/dispatch_test.sh`, faux herdr) et du hook de notification (`node --test mac/test/notify_hook_test.mjs`, faux APNs) |
| `bin/local-ci [push]` | `bin/lint` puis tous les tests, iOS sauté si le diff depuis `origin/main` n'est que de la doc ; `push` pousse d'abord le HEAD (lease, jamais `main`), pose « Local CI » en pending sur ce commit puis en success, failure (étape en échec, HEAD ou worktree modifié pendant le run) ou error (Ctrl-C, TERM, HUP) ; sans `push`, aucun statut |
| `bin/open-ios-xcode` | génère puis ouvre le projet |
| `bin/render-ios-icon` | régénère AppIcon et logo depuis `docs/branding/logo/5-voies-*.svg` (rsvg-convert) |

`main` est protégée sur GitHub : le statut « Local CI » doit être en
success pour merger une PR, sans exiger que la branche soit à jour
(`strict` à false, pas de rebase ni de nouveau run quand `main` a
bougé). Les admins ne sont pas soumis à la règle, pour garder les
pushes directs d'outillage sur `main`. Réglage appliqué avec :

```sh
gh api -X PUT repos/skelz0r/heraldr/branches/main/protection --input - <<'JSON'
{"required_status_checks":{"strict":false,"checks":[{"context":"Local CI"}]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}
JSON
```

Environnement constaté : Xcode 26.2, macOS 26.4.1, iPhone 16 Pro
(`iphone` sur Tailscale) compatible Apple Intelligence.

Push impose un App ID explicite, que le profil wildcard ne couvre pas.
Xcode n'a pas de compte Apple sur ce Mac : `bin/run-ios-device` passe
à `xcodebuild` la clé API App Store Connect de local_events
(`~/.private_keys/AuthKey_KEYID12345.p8`, issuer
`00000000-0000-0000-0000-000000000000`), qui crée App ID et profil.

UUID CoreDevice de l'iPhone par défaut dans `bin/run-ios-device` :
`00000000-0000-0000-0000-000000000001`, surchargeable par argument ou
`IOS_DEVICE_UUID`. Signature automatique avec l'équipe `ABCDE12345`.

`devicectl` ne voit l'iPhone qu'en USB ou sur le même LAN (Bonjour, qui
ne traverse pas Tailscale) : ailleurs il le liste `unavailable` et
l'install échouait (« unable to locate a device matching the requested
device identifier »). `bin/run-ios-device` confie donc l'install à
`~/.agents/skills/ios-device-install/scripts/install-ios-app`, qui publie
alors le build sur
`https://<mac>.<tailnet>.ts.net/ios-ota/com.skelz0r.heraldr.dev/`, à
ouvrir dans Safari sur l'iPhone. Le profil de dev contient déjà l'UDID
de l'iPhone : pas d'archive ni d'export.

Deux écarts avec Heeler, qui compile avec Xcode 26.6 :

- le compilateur d'Xcode 26.2 lève à tort une erreur de concurrence
  dans `SessionDriver.swift` ; `Vendor/patches/` la contourne, appliqué
  par `bin/generate-ios`, et le submodule ignore cette modification
- les xcframework n'ont pas de tranche simulateur x86_64, exclue du
  build simulateur

Le skill `dev-ios` couvre les builds distants sur build-mac si besoin.

## Hook des agents

`.claude/settings.json` déclare un hook Stop : quand l'agent s'apprête
à rendre la main, `.claude/hooks/lint-before-stop` lance `bin/lint`
(2 s) si le worktree est sale ou la branche en avance sur
`origin/main`, et rend le code 2 avec les erreurs sur stderr, que
Claude Code renvoie à l'agent pour qu'il corrige avant de répondre.
Une seule relance par tour (`stop_hook_active`) pour ne jamais boucler.
Ni build ni tests.

## Simulateur et captures

Commandes utiles pour regarder l'app à la main, toujours par `--udid`
ou udid, jamais `booted` (plusieurs worktrees partagent la machine) :

- lancer sur le faux Mac : `xcrun simctl launch <udid>
  com.skelz0r.heraldr.dev -HeraldrFakeMac demo` (presets : `demo`,
  `history`, `question`, `unpaired`, `unreachable`, `connecting`,
  `empty`), ou `SIMCTL_CHILD_HERALDR_FAKE_MAC='<json>'` pour un
  scénario entier
- `xcrun simctl ui <udid> appearance dark|light`, `status_bar <udid>
  override --time 9:41`, `io <udid> screenshot <fichier>`
- AXe : `axe describe-ui --udid <udid>`, `axe tap --id <identifier>
  --udid <udid>`, `axe type '<texte>' --udid <udid>`

Un simulateur resté longtemps démarré peut ignorer le changement
d'apparence (tout reste clair) : `xcrun simctl shutdown` puis `boot`
le remet d'aplomb.
