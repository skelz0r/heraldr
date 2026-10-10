# Spécification MVP

## Conventions herdr supposées

Chaque workspace herdr suit la même organisation :

- tab 1 : un ou plusieurs Claude et un shell
- tabs suivants : un worktree chacun

Le workspace principal est celui dont le label est `~`.

## Écran principal

Liste de tous les workspaces herdr :

- `~` en premier, puis les autres dans l'ordre herdr (`number`)
- une ligne par workspace : label, et un dot d'état agrégé
  (`agent_status` de `herdr workspace list`)
  - gris : idle
  - bleu animé : working
  - orange : blocked (attend une réponse, à donner dans Claude mobile ou
    sur le Mac)
  - vert : done
- badge supplémentaire « en attente » quand un envoi est en file pour ce
  workspace (voir Agent occupé)
- tap sur une ligne : elle devient la cible des envois (sélection
  visuelle forte). C'est le seul sens de « focus » : rien ne bouge sur le
  Mac
- au lancement de l'app, la cible est toujours `~`
- rafraîchissement : au retour au premier plan, en pull-to-refresh, après
  chaque envoi

En bas, trois boutons dans cet ordre : write, voice, paste. Grands, voice
nettement plus grand que les deux autres.

Disposition retenue : direction D des [protos](protos/) (cible en grand
dans la moitié haute, grille de workspaces sur deux colonnes en bas),
avec l'orbe de la direction B en bas : un bouton voix d'environ 180 pt,
en saillie au-dessus de la barre Écrire / Coller, qui déborde sur la
grille.

## Flux d'envoi

Les trois boutons mènent au même écran d'aperçu :

- en tête : la cible rappelée (« → acme_app »), modifiable
- le texte, éditable
- un bouton Envoyer

Sources :

- write : ouvre l'aperçu vide, clavier actif
- voice : enregistrement, transcription en direct sur l'appareil
  (SpeechAnalyzer, framework Speech), puis nettoyage par Foundation
  Models (retirer hésitations, répétitions, faux départs, sans changer le
  sens ni ajouter de contenu), puis aperçu
- paste : lit le presse-papier et ouvre l'aperçu pré-rempli

## Ce que fait un envoi

Cible : l'agent herdr nommé `<slug>-main` dans le tab 1 du workspace.

1. Si l'agent n'existe pas : split d'un pane dans le tab 1 (cwd du
   workspace) et lancement de Claude en yolo mode, avec le nom Remote
   Control `<label>—main` (voir architecture)
2. Si l'agent est `idle` ou `done` : `/clear`, puis le prompt enveloppé
3. Si l'agent est `working` ou `blocked` : l'envoi est mis en file sur
   le Mac et part dès que l'agent redevient `idle` ou `done`

Le prompt envoyé est le texte de l'utilisateur, enveloppé dans une
consigne fixe en français, versionnée dans le dépôt :

```text
Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale :
attention aux erreurs de transcription).

<texte>

Consignes :
- explore le code pour comprendre la demande, ne modifie rien ici
- si la demande est ambiguë, pose tes questions avec AskUserQuestion
- termine obligatoirement en dispatchant le travail avec /start
```

## Nommage

- agent herdr : `slug(label)-main`
  - slug : minuscules, tout caractère hors `[a-z0-9_-]` devient `-`,
    tronqué à 27 caractères, `~` devient `home`
  - exemples : `home-main`, `acme_app-main`,
    `herdr-ios-companion-main`
  - contrainte herdr : `[a-z][a-z0-9_-]{0,31}`, unique parmi les agents
    vivants
- session Claude (Remote Control, visible dans Claude mobile) :
  `<label>—main`, `~` devient `home` (format à valider)

## Configuration

Pairing par QR via l'action `heeler.pair` du plugin Heeler déjà installé
(voir architecture). Une seule machine dans le MVP.

## Hors MVP

- réponse aux questions de l'agent depuis l'app
- push notifications
- détail par agent
- multi-machines
- historique des envois
