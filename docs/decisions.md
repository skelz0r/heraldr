# Journal des décisions

Issu de la session de cadrage du 2026-10-10.

| Sujet | Décision | Écarté |
| --- | --- | --- |
| Positionnement | télécommande de dispatch, complément de Heeler | remplacer Heeler |
| Transport | SSH comme Heeler (streamlocal sur herdr.sock), LAN ou Tailscale | bridge HTTP, daemon |
| Côté Mac | plugin Heeler réutilisé tel quel, aucun code à nous | plugin forké |
| Pairing | QR `HERDR-PAIR:1` de `heeler.pair` | système maison |
| Lib SSH iOS | package HeelerSSH (libssh2) | Citadel |
| Focus | sélection de la cible dans l'app, rien côté Mac | `workspace focus` sur le Mac |
| Cible par défaut | toujours `~` au lancement | dernier utilisé |
| Agent cible | agent nommé `<slug>-main` dans le tab 1, créé s'il manque | adopter un Claude existant |
| Lancement | équivalent `dclaude` (yolo) via `herdr agent start --kind claude -- --dangerously-skip-permissions` | |
| Session Claude | nommée `<label>—main` en Remote Control | |
| Agent occupé | file d'attente, process détaché sur le Mac | refus, interruption, file dans l'app |
| Dispatch | /clear puis prompt + consigne FR qui impose /start | `/start <prompt>` direct |
| Questions de l'agent | autorisées (AskUserQuestion), réponse via Claude mobile ou le Mac | réponse dans l'app |
| Voix | SpeechAnalyzer + nettoyage Foundation Models, aperçu avant envoi | envoi auto, reformulation structurée |
| Flux | aperçu commun aux trois boutons | paste direct |
| États MVP | dot d'état agrégé par workspace | liste nue |
| Projet Xcode | XcodeGen + scripts bin/ | `.xcodeproj` versionné |
| Protos | HTML statiques (decision-mockups) | SwiftUI Previews |
| Bouton Coller | bouton sur mesure + « Toujours autoriser » dans Réglages | `PasteButton` système |
| Direction UI | D (cible en haut, grille en bas) avec un bouton voix d'environ 180 pt en bas, à la place du 128 pt | A, B, C |
| Intégration HeelerSSH | submodule git `Vendor/Heeler` épinglé, package local pour XcodeGen | copie vendorisée |
| Nom | Heraldr (Herald + herdr), bundle id `com.skelz0r.heraldr.dev` | Compagnon (provisoire), Stentor, Heraldz0r, Cooee… |
| Logo | Voix et voies du premier tour, version noire (`5-voies-dark.svg`), palette vert d'eau ; trait épaissi de 60 à 80 px pour l'icône | Éventail et ses variantes, Troupeau |
