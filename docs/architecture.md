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

Rien d'autre à installer pour le MVP.

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
   `~/.local/state/herdr-compagnon/dispatch.sh` (toujours la version de
   l'app installée)
2. `enqueue <workspace_id> <agent> <label_base64>` : le prompt enveloppé
   arrive brut sur stdin et devient un job
   `~/.local/state/herdr-compagnon/jobs/<horodatage>-<id>/`, puis le
   script lance son runner détaché :
   `nohup /bin/sh dispatch.sh run <agent> </dev/null >/dev/null 2>&1 &`

Un job est un dossier de fichiers texte : `workspace_id`, `agent`,
`label`, `prompt`, `state` (`queued`, `sending`, `sent`, `failed`) et
`error`. `dispatch.sh status` les liste en lignes tabulées pour l'app.

Le runner, détaché, survit à la mise en veille du téléphone (spike 7).
Il fixe son PATH (`/opt/homebrew/bin` absent en exec SSH), prend le
verrou de l'agent (`mkdir` atomique, pid dedans pour reprendre un verrou
mort) et traite les jobs de l'agent dans l'ordre d'horodatage :

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
6. `herdr agent prompt <agent> "<prompt enveloppé>"` sans attendre la
   fin du travail
7. `state` passe à `sent`, ou `failed` avec l'erreur ; les jobs `sent`
   sont supprimés après une heure, les `failed` après un jour

Un second envoi vers un agent occupé ne lance pas de deuxième runner :
le verrou est pris, son job attend que le runner en place le traite.
Les envois partent donc dans l'ordre, chacun précédé de son `/clear`.

## App iOS

- Swift 6, SwiftUI, iOS 26 minimum (Liquid Glass, SpeechAnalyzer,
  Foundation Models)
- modules :
  - `Pairing` : scan QR (VisionKit DataScanner), parsing `HERDR-PAIR:1`,
    enrôlement, Keychain
  - `HerdrClient` : requêtes JSON sur streamlocal, modèles Codable
  - `Dispatch` : enveloppe du prompt, slug, exec du script
  - `Voice` : SpeechAnalyzer + nettoyage Foundation Models
  - `UI` : liste, boutons, aperçu
- Foundation Models indisponible (Apple Intelligence off, modèle pas
  prêt) : on garde la transcription brute et on le signale dans l'aperçu
