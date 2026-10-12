# Vision

Le [README](../README.md) dit ce que fait Heraldr et quelles conventions
il impose. Ici, le pourquoi.

## Problème

Une idée de tâche arrive loin du clavier : dans la rue, sur le canapé,
en testant une feature sur le Mac. La transformer en travail d'agent
demande d'ouvrir un terminal, de trouver le bon workspace herdr, le bon
Claude, de faire `/clear`, de taper le prompt, puis de penser à
`/start`. Assez de friction pour que l'idée se perde, ou que la remarque
de QA finisse dans un coin de tête au lieu d'aller au Claude concerné.

## Compagnon du quotidien

Heraldr accompagne le développement au quotidien : il fait le lien entre
le moment où une idée ou une remarque surgit et le Claude qui doit la
traiter. L'app ne montre ni terminal, ni diff, ni fichiers : le travail
se fait et se lit sur le Mac. Elle ne sait que lancer, relancer et
prévenir.

La voix d'abord, parce que c'est ce qui coûte le moins quand on marche
ou qu'on a les mains sur le Mac en pleine QA. Écrire et coller existent,
mais le bouton voix domine l'écran.

## Pourquoi opinionated

Comme un framework opinionated, Heraldr n'a rien à configurer parce
qu'il suppose une organisation unique. C'est ce qui permet à un geste
de suffire :

- un agent par projet au nom prévisible (`<slug>-main`, tab 1) : l'app
  sait à qui parler sans rien demander, et le crée s'il manque
- un `/clear` avant chaque demande : le `main` repart toujours d'un
  contexte vierge, une idée ne pollue pas la suivante
- le `main` explore et pose ses questions, mais ne code pas : il finit
  par `/start`, qui isole chaque feature dans son worktree et son tab.
  Le tab 1 reste disponible pour la prochaine idée
- Home en dispatch global : à la voix, on ne veut pas choisir un projet
  avant de parler. Home est la cible par défaut et relaie au bon `main`
- vers un tab de worktree, l'inverse : pas de consigne ni de `/clear`
  par défaut, parce qu'on y itère sur une feature lancée et que le
  Claude doit garder son contexte

Le prix : Heraldr ne sert à rien à quelqu'un qui organise herdr
autrement. C'est assumé, l'app est faite pour un seul utilisateur et
son Mac.

## Positionnement face à Heeler

[Heeler](https://github.com/ZingerLittleBee/Heeler) est un client iOS
généraliste pour herdr : console de tous les agents, attach terminal,
composer, uploads, diffs, push. Heraldr ne le remplace pas :

- Heeler sert à inspecter et piloter finement, quelle que soit
  l'organisation des workspaces
- Heraldr sert à lancer et faire avancer du travail en quelques
  secondes, à la voix, dans une organisation imposée

Les deux cohabitent sur le même Mac et réutilisent le même plugin herdr
pour l'appairage : chaque app enrôle sa propre clé SSH.

## Ce qui reste hors de l'app

- répondre aux questions d'un `main` : une notification prévient, la
  réponse se fait dans l'app Claude (Remote Control) ou sur le Mac
- suivre l'avancement des worktrees : herdr, Heeler ou l'app Claude ;
  Heraldr ne montre que l'état des `main` et du tab ciblé
- être prévenu par un Claude de worktree : seuls les `main` notifient

## Principes

- gros, lisible, utilisable d'une main en marchant : des cibles tactiles
  généreuses, le bouton voix dominant
- Liquid Glass (iOS 26), peu d'éléments, aucune couleur qui ne porte pas
  d'information ([design](design.md))
- aucune action destructrice silencieuse : jamais de `/clear` sur un
  agent en train de travailler, jamais de repli silencieux vers une
  autre cible
- aucun daemon sur le Mac : SSH, l'API de herdr, un script de file et un
  hook de notifications, que l'app installe elle-même

## Cap

Pistes non livrées, détaillées dans la [roadmap](roadmap.md) : voir où
en est chaque agent d'un workspace, lancer la voix sans ouvrir l'app
(widget, bouton Action, Siri), répondre aux questions sans quitter
Heraldr.
