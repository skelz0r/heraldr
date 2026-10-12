# Spécification

Ce que fait Heraldr, écran par écran, et ce qu'il attend du Mac. Elle
est normative : un écart entre la spec et le code se résout en faveur
de la spec, ou se note dans *Écarts connus* tant qu'il n'est pas
corrigé. Le comment (SSH, runner, hook) est dans
[architecture](architecture.md), le pourquoi dans
[décisions](decisions.md).

## 1. Conventions herdr supposées

Chaque workspace herdr suit la même organisation :

- tab 1 : un ou plusieurs Claude et un shell
- tabs suivants : un worktree chacun

Home est le workspace numéro 1 de herdr, quel que soit son label (`~`,
`Home`…).

## 2. Appairage

Affiché tant qu'aucun Mac n'est appairé.

- consigne : lancer `herdr plugin action invoke heeler.pair` sur le
  Mac, puis scanner le QR, « valable deux minutes »
- scanner QR plein cadre ; sans caméra : « Caméra indisponible : colle
  le code à la place »
- bouton « Coller le code d'appairage » : lit le presse-papier
- seul un texte qui commence par `HERDR-PAIR` déclenche l'appairage ;
  un code déjà scanné n'est renvoyé qu'après un échec
- pendant l'enrôlement : voile « Enrôlement de l'iPhone… »

Refus, affichés sous le scanner. Les deux premiers, et un code expiré
avant l'enrôlement, ne contactent jamais le Mac :

| Cas | Texte |
| --- | --- |
| pas un code `HERDR-PAIR:1` valide | « Ce n'est pas un code d'appairage herdr (<raison>) » |
| code sans clé d'amorçage | « Ce code ne contient pas de clé d'amorçage : relance heeler.pair sur le Mac » |
| code expiré (avant ou pendant l'enrôlement) | « Le code a expiré : relance heeler.pair sur le Mac » |
| `HERDR-ENROLL:ERR:<raison>` | « Le Mac a refusé l'enrôlement (<raison>) » |
| `HERDR-ENROLL:OK` avec une autre empreinte que la clé de l'iPhone | « Enrôlement impossible : le Mac a enrôlé une autre clé (…) » |
| la clé de l'iPhone n'ouvre pas de session après l'enrôlement | « Le Mac n'accepte pas encore la clé de l'iPhone : … » |

La clé hôte du Mac est épinglée par l'empreinte du QR : une autre clé
n'est jamais acceptée. L'adresse qui a répondu passe en tête, les
autres restent en secours (LAN puis Tailscale).

## 3. Connexion au Mac

- au lancement, la cible est toujours Home
- tant que la première liste n'est pas arrivée : « Connexion au Mac… »
- Mac injoignable avant la première liste : « Mac injoignable », le
  détail, bouton « Réessayer ». Une fois une liste arrivée, l'app garde
  la dernière liste et la cible, seule la pastille du Mac passe en
  ambre. Messages :
  - clé hôte différente : « La clé du Mac a changé (…) : refais
    l'appairage »
  - clé de l'iPhone refusée : « Le Mac refuse la clé de cet iPhone :
    refais l'appairage »
  - Tailscale SSH a répondu : « Tailscale SSH a répondu à la place du
    sshd du Mac : désactive-le (RunSSH: false) »
- pastille du Mac en haut (`<user>@<adresse>`, dot : vert en ligne,
  bleu en connexion, ambre injoignable), menu :
  - « Rafraîchir »
  - « Oublier ce Mac », confirmé par « Oublier et réappairer » ; la
    clé reste autorisée sur le Mac tant qu'elle n'est pas retirée de
    `~/.ssh/authorized_keys`
- rafraîchissement : au retour au premier plan, en pull-to-refresh,
  après chaque envoi, puis toutes les 5 s tant qu'un envoi est en file
  ou qu'un agent nommé travaille ; arrêté en arrière-plan

## 4. Écran principal

Disposition : direction D des [protos](protos/), cible en haut sur
environ 38 % de l'écran, grille des workspaces dessous qui défile sous
la cible, en bas une goutte voix d'environ 92 pt entre deux ronds
Écrire et Coller.

### 4.1 Cible

« CIBLE », puis le label (même taille pour tous les workspaces), puis
l'état de son
agent `<slug>-main` et ce que fera le prochain envoi :

| État | Titre | Prochain envoi |
| --- | --- | --- |
| aucun agent `<slug>-main` dans ce workspace | Pas encore d'agent | Un envoi lancera Claude dans le tab 1, nommé `<slug>-main`. |
| envoi en file ou en cours vers ce workspace | Envoi en cours… | Un nouvel envoi partira juste après. |
| `idle` ou `done` | Prêt | Un envoi vide son contexte puis transmet la demande. |
| `working`, envoi de l'app depuis moins d'une heure | Travaille sur ta demande | Un nouvel envoi attendra la fin de son travail. |
| `working` | Travaille | Un nouvel envoi attendra la fin de son travail. |
| `blocked` | Te pose une question : réponds dans Claude mobile | Un nouvel envoi attendra que tu lui aies répondu. |
| état inconnu de herdr | État inconnu | Un nouvel envoi attendra qu'il soit prêt. |

Un agent du même nom dans un autre workspace ne compte pas.

Le nom `<slug>-main` n'est affiché que tant que l'agent n'existe
pas : ailleurs, l'app dit « Claude ». Même règle pour la ligne
d'état de l'aperçu (§5) et les notices après envoi (§6).

### 4.2 Grille

- Home en premier sur toute la largeur, puis les autres sur deux
  colonnes dans l'ordre herdr (`number`)
- par workspace : label, dot de l'état de son agent `<slug>-main`, la
  même source que la cible (§4.1) ; les autres tabs du workspace n'y
  comptent pas :
  - anneau gris : état inconnu ou aucun agent `<slug>-main`
  - pastille verte : idle ou done
  - bleu animé : working, ou envoi en file ou en cours
  - ambre avec halo : blocked
- badge « en attente » quand un envoi vers ce workspace est en file ou
  en cours
- tap : le workspace devient la cible (verre plus clair, nom en gras,
  sans couleur). C'est le seul sens de « focus » : rien ne bouge sur
  le Mac

### 4.3 Boutons

Écrire, voix (goutte), Coller, désactivés sans cible. Écrire et
Coller n'affichent que leur icône, libellée pour VoiceOver. Coller
avec un presse-papier vide : notice d'échec « Presse-papier vide »,
« Copie d'abord le texte à envoyer. »

### 4.4 Historique

Bouton rond à droite de la pilule du Mac, « Historique des envois »
pour VoiceOver. Il ouvre une feuille « Historique » (« Fermer ») qui
liste les envois gardés (§6), du plus récent au plus ancien :

- label du workspace, date relative, statut : une pastille seule de
  10 pt à la couleur de l'état, sans texte, fond ni icône ; jaune
  pleine qui pulse pendant l'envoi, jaune creuse en file, verte une
  fois envoyé, rouge en échec. Couleurs propres à l'historique,
  distinctes de celles des états d'agent. VoiceOver lit l'état
  (Envoi…, En file, Envoyé, Échec)
- le texte, sur quatre lignes au plus ; la raison sous un envoi en
  échec, dans le rouge de « Échec »
- deux actions en icônes seules, grises et sans fond, dans l'en-tête
  de l'entrée juste avant la pastille ; VoiceOver lit leur nom
- « Copier » met le texte dans le presse-papier, puis affiche
  « Copié » deux secondes : l'icône devient une coche dans la couleur
  d'accent
- « Renvoyer » ferme la feuille et renvoie le texte tel quel au
  workspace d'origine, sans passer par l'aperçu : c'est un nouvel envoi
  (§6), avec sa notice et sa propre entrée. Échecs, en notice :
  - workspace d'origine absent de herdr : « <label> n'existe plus »,
    « Copie le texte depuis l'historique pour l'envoyer ailleurs. »
  - workspaces pas encore chargés : « Mac injoignable », « Renvoie la
    demande une fois les workspaces chargés. »
  - envoi refusé : « Échec de l'envoi vers <label> » et la raison
- balayer une entrée la supprime (« Supprimer »)
- sans envoi : « Aucun envoi », « Les 20 derniers envois s'afficheront
  ici. »

### 4.5 Réglages

Bouton rond engrenage à droite du bouton Historique, « Réglages » pour
VoiceOver. Il ouvre une feuille « Réglages » (« Fermer »), à mi-hauteur
et extensible, en deux sections.

« Dictée » : « Corrections », avec leur nombre, ouvre la liste du
lexique de dictée (§5.2), « Corrections de dictée » :

- une ligne par correction, « entendu → voulu », dans l'ordre du
  lexique, les plus récentes d'abord ; en pied, « <n> sur 50, les plus
  récentes d'abord. Les 20 premières guident le nettoyage. »
- balayer une ligne la supprime (« Supprimer ») ; pas de « Tout
  vider »
- taper une ligne ouvre « Modifier la correction », le bouton « + »
  (« Ajouter une correction ») ouvre « Nouvelle correction » : champs
  « Entendu » et « Voulu », sans correction automatique ni majuscule
  imposée, « Annuler » et « Enregistrer »
- « Enregistrer » reste désactivé tant que chaque côté ne compte pas
  de 1 à 3 mots, ou que voulu et entendu sont égaux sans tenir compte
  de la casse, des accents ni de la ponctuation en bord de mot ; les
  espaces et la ponctuation en bord de mot sont retirés à
  l'enregistrement
- une correction enregistrée remonte en tête, comme une correction
  apprise ; un entendu déjà dans le lexique est remplacé ; modifier
  l'entendu retire l'ancien
- les changements sont gardés aussitôt et servent dès la dictée
  suivante
- sans correction : « Aucune correction », « Corrige un mot mal
  entendu dans l'aperçu d'une dictée : la correction s'ajoutera ici à
  l'envoi. » et « Ajouter une correction »

« Build installé » dit quel build tourne :

- « Version » : `CFBundleShortVersionString` (0.1.0, jamais incrémentée)
- « Commit » : SHA court du commit buildé, suffixé `-dirty` si le
  worktree avait des modifications ; « inconnu » hors dépôt git
- « Buildé » : date et heure locales du build ; « inconnu » si absente

Commit et date sont écrits dans l'`Info.plist` du `.app` à chaque build
(`HeraldrBuildCommit`, `HeraldrBuildDate` en ISO 8601 UTC), quel que
soit le chemin : `bin/` ou Xcode.

## 5. Composer une demande

Les trois boutons mènent au même aperçu, sur la cible du moment.

### 5.1 Dictée

- « Préparation du micro… », puis « Parle, je t'écoute. », puis la
  transcription en direct (SpeechAnalyzer, sur l'appareil), onde de
  niveau et chrono
- tant que le micro est actif, l'écran ne se verrouille pas tout seul ;
  le verrouillage automatique revient dès qu'il s'arrête (arrêt,
  annulation, erreur, fermeture de l'écran, passage en arrière-plan),
  donc pas pendant le nettoyage ; un verrouillage manuel ou un
  changement d'app coupe toujours la dictée
- « Annuler » ferme sans rien garder ; depuis une salve lancée de
  l'aperçu (§5.2), il revient à l'aperçu avec son texte intact ;
  « Arrêter la dictée » enchaîne sur le nettoyage
- rien d'entendu : « Rien n'a été entendu. », on reste sur l'écran de
  dictée
- nettoyage par Foundation Models (« Nettoyage… », « Foundation
  Models, sur l'appareil ») : retire hésitations, répétitions et faux
  départs sans changer le sens ni ajouter de contenu
- la transcription brute est gardée quand le modèle est indisponible
  (« Apple Intelligence est désactivé », « le modèle Apple
  Intelligence n'est pas encore prêt », « cet appareil ne gère pas
  Apple Intelligence »), que la dictée est trop longue, ou que le
  résultat fait 40 % ou moins, ou 130 % ou plus, de la longueur brute
  (« nettoyage écarté : il s'éloignait trop de la dictée »)
- les corrections apprises (§5.2) servent à la dictée suivante : le
  texte corrigé est fourni à la transcription comme vocabulaire
  contextuel, et les 20 paires « entendu → voulu » les plus récentes
  sont ajoutées à la consigne du nettoyage, à appliquer quand le
  contexte s'y prête ; aucun remplacement automatique dans le texte
- le nettoyage ne porte que sur la salve qui vient d'être dictée,
  jamais sur le texte déjà dans l'aperçu

### 5.2 Aperçu

- en tête « Aperçu » et « Fermer »
- la cible (« → label »), avec son dot, modifiable par « Changer de
  cible » (liste des workspaces, dot comme dans la grille, badge « en
  attente »)
- l'état de la cible et le prochain envoi (§4.1)
- le texte, éditable, placeholder « Que doit faire l'agent ? » ;
  clavier ouvert pour Écrire, pré-rempli pour Coller et la dictée
- l'origine : « Écrit », « Collé », « Dictée nettoyée », ou
  « Transcription brute : <raison> » ; dès qu'une salve a été dictée,
  l'origine est la dictée, même si le texte vient d'Écrire ou Coller ;
  « Transcription brute » l'emporte si une salve n'a pas été nettoyée,
  avec la raison de la dernière ; « Voir l'original » dès qu'une salve
  a été nettoyée, il montre la transcription brute de chaque salve,
  séparées par un trait
- « Dicter » (texte vide) ou « Dicter la suite » ouvre l'écran de
  dictée (§5.1), quelle que soit l'origine ; la salve nettoyée s'ajoute
  à la fin du texte, après un retour à la ligne, sans toucher au texte
  déjà là, corrigé ou non
- « Envoyer », désactivé tant que le texte est vide ou pendant
  l'envoi ; en cas d'échec, l'erreur s'affiche au-dessus et l'aperçu
  reste ouvert ; en cas de succès il se ferme
- apprentissage des corrections, sans rien afficher : quand on tape
  Envoyer sur une dictée, le texte proposé (nettoyé, ou brut) est
  comparé mot à mot au texte envoyé, sans tenir compte de la casse,
  des accents ni de la ponctuation en bord de mot. Avec plusieurs
  salves, chaque texte proposé est comparé à ce qu'il était devenu
  juste avant la salve suivante, le dernier au texte envoyé ; le texte
  déjà là avant une salve fait partie du texte proposé. Chaque remplacement
  de 1 à 3 mots par 1 à 3 mots est retenu (« entendu → voulu ») ; un
  remplacement d'un seul mot par un seul mot garde le mot suivant (ou
  précédent) inchangé, « on push → git push » plutôt que
  « on → git ». Rien n'est retenu quand plus de la moitié des mots
  proposés ont changé (réécriture), ni pour un ajout ou une
  suppression seuls, ni pour un envoi écrit ou collé
- le lexique est gardé sur l'iPhone : une erreur déjà connue prend la
  nouvelle correction et remonte en tête ; au-delà de 50 corrections,
  les plus anciennes sont oubliées. Il se consulte et se corrige dans
  les Réglages (§4.5)

## 6. Ce que fait un envoi

Cible : l'agent herdr `<slug>-main` dans le tab 1 du workspace.

1. agent absent : split d'un pane du tab 1 (cwd de ce pane) et
   lancement de Claude en yolo mode, nom Remote Control `<label>—main`
   (`~` devient `home`)
2. agent `idle` ou `done` : `/clear`, puis le prompt enveloppé
3. agent `working` ou `blocked` : l'envoi attend sur le Mac et part dès
   qu'il redevient `idle` ou `done`
4. plusieurs envois vers un même agent partent dans l'ordre, chacun
   précédé de son `/clear`
5. un agent du même nom dans un autre workspace n'est jamais visé :
   l'envoi échoue

Notice après l'envoi (5 s, fermée au tap) :

| Agent au moment de l'envoi | Notice |
| --- | --- |
| absent | Envoyé à <label> — Le Mac lance Claude dans le tab 1, nommé <agent>, puis lui transmet la demande. |
| `idle` ou `done` | Envoyé à <label> — Le Mac vide le contexte de Claude, puis lui transmet la demande. |
| autre, ou envoi déjà en file | En file pour <label> — Claude est occupé : la demande partira dès qu'il aura fini. |

Un envoi suivi par l'app qui passe `failed` affiche « Échec de l'envoi
vers <label> » avec sa raison, une seule fois.

Chaque envoi est enregistré sur l'iPhone dès qu'on tape Envoyer, avant
la connexion au Mac : le texte tel que saisi (sans la consigne), le
workspace et la date. Son statut :

| Moment | Statut |
| --- | --- |
| le Mac n'a pas encore répondu | Envoi… |
| job créé, `queued` ou `sending` | En file |
| job `sent` | Envoyé |
| échec avant le Mac, ou job `failed` | Échec, avec la raison |
| encore « Envoi… » au lancement de l'app (crash pendant l'envoi) | Échec, « Envoi interrompu avant la réponse du Mac. » |

Un job purgé par le Mac laisse l'envoi à son dernier statut. Seuls les
20 envois les plus récents sont gardés.

### 6.1 Consigne standard

```text
Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale :
attention aux erreurs de transcription).

<texte>

Consignes :
- explore le code pour comprendre la demande, ne modifie rien ici
- si la demande est ambiguë, pose tes questions avec AskUserQuestion
- termine obligatoirement en dispatchant le travail avec /start
```

### 6.2 Envoi vers Home

Home est la cible par défaut, donc beaucoup de demandes y arrivent alors
qu'elles visent un projet. Son agent `<slug>-main` (`home-main` pour
le label `~`) reçoit une consigne à part :

```text
Demande envoyée depuis l'iPhone vers Home, la cible par défaut de l'app
(peut venir d'une dictée vocale : attention aux erreurs de
transcription).

<texte>

Consignes :
- ne modifie rien ici
- identifie le projet visé parmi les workspaces herdr ouverts : labels
  avec `herdr workspace list`, dossiers avec
  `herdr pane list --workspace <workspace_id>` (cwd)
- si plusieurs projets peuvent correspondre, pose la question avec
  AskUserQuestion avant tout relais
- si un projet est visé, relaie-lui la demande puis arrête-toi, sans
  /start : `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" relay
  <workspace_id>` avec sur l'entrée standard la demande d'origine,
  corrigée des erreurs de transcription évidentes et complétée des
  réponses à tes questions
- si aucun projet ouvert n'est concerné : explore ce qu'il faut pour
  comprendre la demande, pose tes questions avec AskUserQuestion si
  elle est ambiguë et termine obligatoirement en dispatchant le
  travail avec /start
```

Le relais suit le même chemin qu'un envoi de l'app vers ce workspace
(même nom d'agent, création, file, `/clear`, consigne standard) et
s'affiche sur la ligne du projet. Un relais vers Home ou vers un
workspace inconnu est refusé.

### 6.3 Nommage

- agent herdr : `slug(label)-main`
  - slug : minuscules, tout caractère hors `[a-z0-9_-]` devient `-`,
    `w-` devant s'il ne commence pas par une lettre, tronqué à 27
    caractères, `~` devient `home`
  - exemples : `home-main`, `acme_app-main`,
    `herdr-ios-companion-main`, `w-2025-notes-main` ; vecteurs
    partagés par l'app et `dispatch.sh` dans
    `mac/test/agent-names.tsv`
  - contrainte herdr : `[a-z][a-z0-9_-]{0,31}`, unique parmi les agents
    vivants
- session Claude (Remote Control, visible dans Claude mobile) :
  `<label>—main`, `~` devient `home`

## 7. Notifications

- autorisation demandée au premier rafraîchissement réussi, une fois
  par lancement ; accordée, l'app envoie son token au Mac
  (`register-push`) à chaque lancement
- échec de cet envoi : notice « Notifications non installées sur le
  Mac » ; échec de l'enregistrement APNs : « Notifications
  indisponibles »
- une notif part quand un agent `-main` passe `blocked` et le reste
  3 s, une fois par question ; jamais pour les Claude des worktrees.
  Titre : label du workspace, sous-titre : agent, corps : texte de
  l'AskUserQuestion, « Demande d'autorisation : <outil> », ou « Attend
  une réponse »
- notif reçue app ouverte : bannière, liste et son
- tap : le workspace de l'agent devient la cible, puis la session
  s'ouvre dans l'app Claude. Si le lien manque ou que l'app Claude ne
  le prend pas : carte « <agent> attend une réponse », « La session ne
  s'est pas ouverte dans Claude. », bouton « Ouvrir dans Claude »

## 8. Contrat avec le Mac

L'app ne parle au Mac que par SSH, et ce contrat change en même temps
des deux côtés : le script est réinstallé par l'app avant chaque
`enqueue` et `register-push`, le hook avec `register-push`. `status`
lit le script déjà installé, qui peut venir d'une version précédente
de l'app : sa sortie reste lisible par l'app plus récente.

### 8.1 API herdr (`herdr.sock`)

- `workspace.list` : `workspace_id`, `number`, `label` ; son
  `agent_status`, agrégé sur tous les tabs, n'est pas lu
- `agent.list` : `name` (absent pour un Claude lancé à la main),
  `workspace_id`, `tab_id`, `agent_status`
- tolérance : tout autre champ est ignoré, un `agent_status` inconnu
  devient « État inconnu »

### 8.2 `dispatch.sh`

| Commande | Entrée standard | Sortie |
| --- | --- | --- |
| `install` | le script | rien |
| `enqueue <workspace_id> <agent> <label_base64>` | prompt enveloppé | id du job |
| `relay <workspace_id>` | demande brute | id du job ; code 2 vers Home ou un workspace inconnu |
| `status` | rien | une ligne par job : `id`, `workspace_id`, `agent`, `state`, `error`, séparés par des tabulations |
| `register-push <token> <sandbox\|production> <topic> <team_id>` | le hook | rien |

- `state` : `queued`, `sending`, `sent`, `failed` ; l'app ignore une
  ligne d'état inconnu
- `error` : sur une ligne, tabulations et retours remplacés par des
  espaces
- les jobs `sent` disparaissent après une heure, les `failed` après un
  jour
- `register-push` refuse un token hors `[0-9a-f]{64,200}`, une équipe
  hors `[A-Z0-9]{10}`

### 8.3 Payload des notifications

`aps.alert` (`title`, `subtitle`, `body`), `workspace_id`, `agent` et
`session_url` facultatif. Sans `workspace_id` ou `agent`, le tap est
ignoré.

## 9. Écarts connus

- E1 : un emoji composé (drapeau, teinte de peau) dans un label compte
  pour un caractère dans l'app et pour plusieurs dans `dispatch.sh` :
  un relais de Home vers ce workspace viserait un autre agent que
  l'app.
- E2 : quand deux envois suivis passent `failed` entre deux
  rafraîchissements, seul le premier est annoncé ; le second ne l'est
  jamais.
- E3 : un workspace autre que Home labellisé `~` vise `home-main` dans
  l'app et `w---main` dans un relais de Home.

## 10. Hors périmètre

- réponse aux questions de l'agent depuis l'app
- notif de fin de tâche
- détail par agent
- multi-machines, sessions herdr nommées
