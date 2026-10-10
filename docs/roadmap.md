# Roadmap

## V1 : MVP

Voir [mvp.md](mvp.md).

## V2 : être prévenu quand un workspace a besoin de moi

Objectif : savoir sans regarder qu'un agent attend, et savoir lequel et
pourquoi.

- push notification quand un agent passe `blocked`, ou `done` après un
  envoi depuis l'app
- contenu : workspace, tab (worktree), nom de l'agent, type d'attente
  (question, permission, fin de tâche)
- pastille de compteur sur la ligne du workspace et sur l'icône de l'app
- tap sur la notif : ouvre l'app sur le workspace, avec la liste de ce
  qui attend et qui attend (tab par tab)

Mécanique envisagée, sur le modèle de Heeler :

- hook herdr `pane.agent_status_changed` (plugin à nous, ou
  réutilisation de `notify-hook.js` de Heeler) avec debounce, revérif
  de l'état et dédup
- payload chiffré AES-256-GCM avec une clé par machine générée sur le
  téléphone
- relay APNs à nous (Cloudflare Worker, ~3 fichiers repris de
  `relay/` de Heeler) avec notre clé `.p8` et notre bundle id : le relay
  de Heeler ne signe que pour son app
- Notification Service Extension pour déchiffrer

Prérequis : compte développeur payant (déjà le cas pour local_events),
capability Push.

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

- multi-machines (plusieurs QR)
- historique des envois et renvoi rapide
- widget et action du bouton Action pour lancer directement la voix
- raccourci Siri « dispatch dans acme »
