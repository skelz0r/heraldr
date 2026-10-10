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
| `bin/setup-ios` | vérifie Xcode 26, xcode-select, XcodeGen, initialise le submodule Heeler |
| `bin/generate-ios` | `xcodegen generate`, applique `Vendor/patches/*.patch` au submodule |
| `bin/build-ios [simulator\|device]` | build |
| `bin/run-ios` | build et lancement simulateur |
| `bin/run-ios-device [uuid]` | build puis install sur l'iPhone par le skill global `ios-device-install` : `devicectl` si l'iPhone est joignable, sinon page d'install OTA via Tailscale (attente device busy, déverrouillage keychain CI comme local_events) |
| `bin/run-ios-tests [suite]` | tests unitaires en simulateur (`IOS_TEST_SIMULATOR_NAME`, iPhone 17 Pro par défaut), puis `bin/run-mac-tests` |
| `bin/run-mac-tests` | tests du script de dispatch (`mac/test/dispatch_test.sh`, faux herdr) et du hook de notification (`node --test mac/test/notify_hook_test.mjs`, faux APNs) |
| `bin/local-ci [push]` | tous les tests, iOS sauté si le diff depuis `origin/main` n'est que de la doc ; `push` pousse le HEAD validé et pose le statut « Local CI » |
| `bin/open-ios-xcode` | génère puis ouvre le projet |
| `bin/render-ios-icon` | régénère AppIcon et logo depuis `docs/branding/logo/5-voies-*.svg` (rsvg-convert) |

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
