# Roadmap

## V1 : MVP

Voir [spec.md](spec.md).

## V2 : être prévenu quand un workspace a besoin de moi

Objectif : savoir sans regarder qu'un agent attend, et savoir lequel et
pourquoi.

Livré, en version resserrée :

- push notification quand un agent `<slug>-main` passe `blocked`
  (question AskUserQuestion ou demande de permission), et seulement
  eux : les Claude des worktrees lancés par `/start` sont ignorés
- contenu : label du workspace, nom de l'agent, texte de la question
- tap sur la notif : ouvre directement la session Remote Control de
  l'agent dans l'app Claude, sinon Heraldr sur le workspace avec un
  bouton « Ouvrir dans Claude »
- envoi APNs direct depuis le Mac par un plugin herdr, sans relay ni
  daemon (voir [architecture](architecture.md), Notifications)

Écartés pour l'instant :

- notif de fin de tâche (`done`)
- tab (worktree) et agents hors `-main`
- pastille de compteur sur la ligne du workspace et sur l'icône
- relay Cloudflare Worker à la Heeler, payload chiffré AES-256-GCM et
  Notification Service Extension : le payload transite en clair par
  APNs (label, nom d'agent, texte de la question)

Question ouverte : répondre aux questions directement depuis la notif ou
l'app (lecture de l'écran de l'agent puis `send-keys`) ou continuer à
renvoyer vers Claude mobile.

## V3 : voir où en est chaque agent

- écran de détail d'un workspace : un dot par agent (Claude main, shell,
  agents des worktrees), groupés par tab
- label du tab = nom du worktree, dernier état, depuis quand
- flux live via `events.subscribe` sur streamlocal plutôt que du polling
- éventuellement Live Activity pour un dispatch en cours

## Idées non priorisées

- passer à Xcode 26.6 (ou 27) : celui de Heeler, qui retirerait le
  patch de `SessionDriver.swift` ; à faire dans une branche dédiée,
  avec `bin/local-ci` et `bin/qa --all`
- multi-machines (plusieurs QR)
- widget et action du bouton Action pour lancer directement la voix
- raccourci Siri « dispatch dans acme »
- script d'analyse du journal des dictées (`mac/dictation-report.mjs`) :
  part de mots retouchés par semaine, remplacements défaits par paire
  entendu → terme, indices suivis, selon la recette de
  `docs/architecture.md` ; à écrire après quelques semaines de dictées
  réelles dans `~/.config/heraldr/journal-dictees.jsonl`
