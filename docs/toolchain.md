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
| `bin/setup-ios` | vérifie Xcode 26, xcode-select, XcodeGen |
| `bin/generate-ios` | `xcodegen generate` |
| `bin/build-ios [simulator\|device]` | build |
| `bin/run-ios` | build et lancement simulateur |
| `bin/run-ios-device [uuid]` | build, install et lancement sur l'iPhone (attente device busy, déverrouillage keychain CI comme local_events) |
| `bin/run-ios-tests` | tests unitaires |
| `bin/open-ios-xcode` | génère puis ouvre le projet |

Environnement constaté : Xcode 26.2, macOS 26.4.1, iPhone 16 Pro
(`iphone` sur Tailscale) compatible Apple Intelligence.

Le skill `dev-ios` couvre les builds distants sur build-mac si besoin.
