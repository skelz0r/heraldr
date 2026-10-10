# Vision

## Problème

Une idée de tâche arrive loin du Mac (dans la rue, sur le canapé). La
transformer en travail d'agent demande aujourd'hui d'ouvrir un terminal,
de trouver le bon workspace herdr, le bon Claude, de faire `/clear`, de
taper le prompt, puis de penser à faire `/start`. Trop de friction : l'idée
se perd.

## Proposition de valeur

Un geste, un résultat : appuyer sur le gros bouton voix, parler, relire,
envoyer. Le Claude principal du workspace choisi reçoit la demande sur un
contexte vierge, explore le code, pose ses questions s'il le faut, puis
dispatche le travail dans un nouveau worktree via `/start`.

L'app ne fait que ça. Elle ne montre ni terminal, ni diff, ni fichiers.

## Positionnement face à Heeler

[Heeler](https://github.com/ZingerLittleBee/Heeler) est un client iOS
généraliste pour herdr : console de tous les agents, attach terminal,
composer, uploads, diffs, push. Il est déjà installé côté Mac.

Ce projet ne le remplace pas, il le complète :

- Heeler sert à inspecter et piloter finement
- le compagnon sert à lancer du travail en quelques secondes, à la voix

Les deux cohabitent sur le même Mac en réutilisant le même plugin herdr
(pairing Heeler) : chaque app enrôle sa propre clé SSH.

## Ce qui reste hors de l'app

- répondre aux questions du Claude principal : Claude mobile (Remote
  Control) ou le Mac
- suivre le travail dispatché dans les worktrees : herdr, Heeler, Claude
  mobile

## Principes

- gros, lisible, utilisable d'une main en marchant : pas un look natif
  standard, des cibles tactiles généreuses, le bouton voix dominant
- Liquid Glass (iOS 26) pour une UI propre
- aucune action destructrice silencieuse : jamais de `/clear` sur un
  agent en train de travailler
- aucun code ni service côté Mac à maintenir dans le MVP
