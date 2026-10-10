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
| `bin/run-ios-device [uuid]` | build, install et lancement sur l'iPhone (attente device busy, déverrouillage keychain CI comme local_events) |
| `bin/run-ios-tests [suite]` | tests unitaires en simulateur, puis tests du script de dispatch (`mac/test/dispatch_test.sh`) |
| `bin/open-ios-xcode` | génère puis ouvre le projet |

Environnement constaté : Xcode 26.2, macOS 26.4.1, iPhone 16 Pro
(`iphone` sur Tailscale) compatible Apple Intelligence.

UUID CoreDevice de l'iPhone par défaut dans `bin/run-ios-device` :
`00000000-0000-0000-0000-000000000001`, surchargeable par argument ou
`IOS_DEVICE_UUID`. Signature automatique avec l'équipe `ABCDE12345`.

Deux écarts avec Heeler, qui compile avec Xcode 26.6 :

- le compilateur d'Xcode 26.2 lève à tort une erreur de concurrence
  dans `SessionDriver.swift` ; `Vendor/patches/` la contourne, appliqué
  par `bin/generate-ios`, et le submodule ignore cette modification
- les xcframework n'ont pas de tranche simulateur x86_64, exclue du
  build simulateur

Le skill `dev-ios` couvre les builds distants sur build-mac si besoin.
