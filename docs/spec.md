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

- au lancement, la cible est toujours Home (son `main`)
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
  après chaque envoi, puis toutes les 5 s tant qu'un envoi est en file,
  qu'un agent nommé travaille ou que le Claude du tab ciblé (§4.2)
  travaille ; arrêté en arrière-plan

## 4. Écran principal

Disposition : direction D des [protos](protos/), cible en haut sur
environ 38 % de l'écran, grille des workspaces dessous qui défile sous
la cible, en bas une goutte voix d'environ 92 pt entre deux ronds
Écrire et Coller.

### 4.1 Cible

« CIBLE », puis le label (même taille pour tous les workspaces), en
dessous en plus petit et en secondaire `main`, ou le nom du tab quand
un tab est ciblé (§4.2), puis l'état de son agent `<slug>-main` et ce
que fera le prochain envoi :

| État | Titre | Prochain envoi |
| --- | --- | --- |
| aucun agent `<slug>-main` dans ce workspace | Pas encore d'agent | Un envoi lancera Claude dans le tab 1, nommé `<slug>-main`. |
| envoi en file ou en cours vers cet agent | Envoi en cours… | Un nouvel envoi partira juste après. |
| `idle` ou `done` | Prêt | Un envoi vide son contexte puis transmet la demande. |
| `working`, envoi de l'app depuis moins d'une heure | Travaille sur ta demande | Un nouvel envoi attendra la fin de son travail. |
| `working` | Travaille | Un nouvel envoi attendra la fin de son travail. |
| `blocked` | Te pose une question : réponds dans Claude mobile | Un nouvel envoi attendra que tu lui aies répondu. |
| état inconnu de herdr | État inconnu | Un nouvel envoi attendra qu'il soit prêt. |

Un agent du même nom dans un autre workspace ne compte pas. Un envoi
vers un tab du workspace n'occupe pas son `<slug>-main`.

Cible tab : l'état est celui du premier Claude du tab (ordre de
`agent.list`), mêmes lignes sauf :

| État | Titre | Prochain envoi |
| --- | --- | --- |
| plus aucun Claude dans le tab | Plus de Claude dans ce tab | Un envoi échouera : relance Claude dans ce tab sur le Mac. |
| `idle` ou `done` | Prêt | Un envoi transmet la demande telle quelle, sans vider son contexte. (avec « Envoyer /clear avant » coché dans l'aperçu : Un envoi vide son contexte puis transmet la demande.) |

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
  en cours, vers son `main` ou l'un de ses tabs
- tap : le `main` du workspace devient la cible (verre plus clair, nom
  en gras, sans couleur), même si un de ses tabs était ciblé. C'est le
  seul sens de « focus » : rien ne bouge sur le Mac
- appui long : menu « Cibler un tab de <label> », avec « main » puis
  les tabs du workspace hors tab 1 qui contiennent au moins un Claude
  sans nom herdr,
  dans l'ordre herdr (`number`), nommés par leur label herdr (« tab
  <n> » sans label) ; sans tel tab : « Aucun Claude dans les autres
  tabs ». Choisir un tab en fait la cible ; la tuile cible affiche son
  nom sous le label, sa pastille reste celle du `<slug>-main`
- le tab ciblé n'est pas gardé : il le reste jusqu'au prochain tap,
  au relancement (retour sur Home) ou à la disparition du tab dans
  herdr (retour sur le `main` du workspace)

### 4.3 Boutons

Écrire, voix (goutte), Coller, désactivés sans cible. Écrire et
Coller n'affichent que leur icône, libellée pour VoiceOver. Coller
reprend le texte et les images du presse-papier (trois au plus, comme
dans l'aperçu, §5.2). Presse-papier sans texte ni image : notice
d'échec « Presse-papier vide », « Copie d'abord le texte ou la capture
à envoyer. »

### 4.4 Historique

Bouton rond à droite de la pilule du Mac, « Historique des envois »
pour VoiceOver. Il ouvre une feuille « Historique », sans bouton
Fermer (on la glisse vers le bas), à deux segments en tête, « Tâches »
(ouvert par défaut) et « Questions ».

« Tâches » liste les envois gardés (§6) sans réponse, du plus récent
au plus ancien. Une question reste là tant que sa réponse n'est pas
arrivée : l'app ne sait qu'une demande était une simple question qu'en
recevant la réponse (§6.5).

- label du workspace (`<label> — <tab>` pour un envoi vers un tab),
  date relative, statut : une pastille seule de
  10 pt à la couleur de l'état, sans texte, fond ni icône ; jaune
  pleine qui pulse pendant l'envoi, jaune creuse en file, verte une
  fois envoyé, rouge en échec. Couleurs propres à l'historique,
  distinctes de celles des états d'agent. VoiceOver lit l'état
  (Envoi…, En file, Envoyé, Échec)
- le texte, sur quatre lignes au plus ; « 1 capture jointe » ou
  « <n> captures jointes » en secondaire dessous quand l'envoi en
  avait ; la raison sous un envoi en échec, dans le rouge de « Échec »
- deux actions en icônes seules, grises et sans fond, dans l'en-tête
  de l'entrée juste avant la pastille ; VoiceOver lit leur nom
- « Copier » met le texte dans le presse-papier, sans les captures, puis affiche
  « Copié » deux secondes : l'icône devient une coche dans la couleur
  d'accent
- « Renvoyer » ferme la feuille et renvoie le texte tel quel au
  workspace d'origine, ou au tab d'origine avec le même choix de
  `/clear`, avec les chemins des captures déjà posées sur le Mac (sans
  les renvoyer : passé une semaine, le Mac les a effacées et Claude ne
  les trouvera plus), sans passer par l'aperçu : c'est un nouvel envoi (§6), avec
  sa notice et sa propre entrée. Échecs, en notice :
  - workspace ou tab d'origine absent de herdr : « <label> n'existe
    plus » (`<label> — <tab>` pour un tab),
    « Copie le texte depuis l'historique pour l'envoyer ailleurs. »
  - workspaces pas encore chargés : « Mac injoignable », « Renvoie la
    demande une fois les workspaces chargés. »
  - envoi refusé : « Échec de l'envoi vers <label> » et la raison
- balayer une entrée la supprime (« Supprimer »)
- sans envoi : « Aucun envoi », « Les 20 derniers envois s'afficheront
  ici. »

« Questions » liste les envois qui ont reçu une réponse, du plus récent
au plus ancien :

- label du workspace, date relative de la réponse
- la question, en secondaire sur deux lignes au plus, puis le résumé
  de la réponse sur trois lignes au plus
- tap : la réponse complète (§6.5) dans la même feuille, retour par la
  flèche, « Copier » en haut à droite
- balayer une entrée la supprime (« Supprimer »)
- sans réponse : « Aucune question », « Les réponses aux 20 dernières
  questions s'afficheront ici. »

### 4.5 Réglages

Bouton rond engrenage à droite du bouton Historique, « Réglages » pour
VoiceOver. Il ouvre une feuille « Réglages », sans bouton Fermer (on
la glisse vers le bas), à mi-hauteur et extensible, en deux sections.

« Dictée » : « Lexique », avec le nombre de termes, ouvre la liste du
lexique de dictée (§5.2), « Lexique de dictée » :

- une ligne par terme, dans l'ordre du lexique, les plus récents
  d'abord : le terme, et dessous ses variantes entendues séparées par
  des virgules ; en pied, « Les plus récents d'abord. Une variante
  saisie ici, ou de plusieurs mots, est remplacée par son terme dans
  chaque dictée ; une variante apprise d'un seul mot est seulement
  signalée au nettoyage. », puis l'état de la sauvegarde sur le Mac
  (§5.2) : « Sauvegardé sur le Mac <il y a …>. », « Pas encore
  sauvegardé sur le Mac : ce sera fait à la prochaine connexion. » ou,
  restauration en attente, « Le lexique sauvegardé sur le Mac sera
  repris à la prochaine connexion. »
- balayer une ligne supprime le terme et ses variantes
  (« Supprimer ») ; pas de « Tout vider »
- taper une ligne ouvre « Modifier le terme », le bouton « + »
  (« Ajouter un terme ») ouvre « Nouveau terme » : section « Terme »
  (un champ), section « Variantes entendues » (un champ « Entendu » par
  variante, plus un vide, balayer pour retirer, « Ajouter une
  variante »), sans correction automatique ni majuscule imposée,
  « Annuler » et « Enregistrer »
- « Enregistrer » reste désactivé tant que le terme et chaque variante
  remplie ne comptent pas de 1 à 3 mots, ou que deux d'entre eux sont
  égaux sans tenir compte de la casse, des accents ni de la
  ponctuation en bord de mot ; les champs vides sont ignorés, les
  espaces et la ponctuation en bord de mot retirés à l'enregistrement
- un terme enregistré remonte en tête ; une variante qui appartenait à
  un autre terme passe à celui-ci ; un terme renommé comme un autre
  terme existant fusionne avec lui. Une variante ajoutée ou modifiée
  ici, même seulement en casse ou en accents, est « saisie », une
  variante gardée telle quelle garde son origine ; un terme nouveau,
  renommé ou enregistré sans variante est « saisi », sinon il garde la
  sienne
- les changements sont gardés aussitôt et servent dès la dictée
  suivante
- sans terme : « Aucun terme », « Corrige un mot mal entendu dans
  l'aperçu d'une dictée : le terme s'ajoutera ici à l'envoi, avec ce
  qui avait été entendu. » et « Ajouter un terme »

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
  changement d'app coupe toujours la dictée, qui enchaîne sur le
  nettoyage comme « Arrêter la dictée » : au retour, l'aperçu montre
  ce qui a été dicté
- fermer l'écran pendant la dictée l'annule
- le micro interrompt la musique ou le son d'une autre app (Spotify…)
  au lieu de jouer par-dessus, et la rend dès qu'il s'arrête (arrêt,
  annulation, erreur, arrière-plan, fermeture de l'écran), avant la
  fin de la transcription : l'app prévient le système pour que l'autre
  app reprenne d'elle-même, si elle le gère
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
- le lexique (§5.2) sert à la dictée suivante :
  - les 100 termes les plus récents sont fournis à la transcription
    comme vocabulaire contextuel
  - remplacement par le code, avant le nettoyage puis sur son résultat,
    et aussi quand la transcription brute est gardée : chaque variante
    saisie, chaque variante de deux mots ou plus, et le terme lui-même
    s'il est saisi ou fait deux mots ou plus, devient le terme, écrit
    avec sa casse. Mots entiers seulement (séparés par des espaces, la
    ponctuation en bord de mot ne compte pas), sans tenir compte de la
    casse ni des accents ; les mots d'une variante ne sont séparés que
    par des espaces ; la variante la plus longue passe d'abord et un
    mot déjà remplacé ne l'est pas deux fois
  - une variante apprise d'un seul mot n'est jamais remplacée : quand
    elle apparaît dans la transcription, elle est signalée à la
    consigne du nettoyage (« « <entendu> » veut peut-être dire
    « <terme> » », à remplacer seulement si la phrase n'a pas de sens
    autrement), 3 au plus, les plus souvent corrigées puis les plus
    récentes ; sans variante présente, la consigne est inchangée
  - « Voir l'original » montre la transcription avant tout remplacement,
    et apparaît aussi pour une transcription brute que le remplacement
    a modifiée
- le nettoyage ne porte que sur la salve qui vient d'être dictée,
  jamais sur le texte déjà dans l'aperçu

### 5.2 Aperçu

- en tête « Aperçu » et « Fermer »
- la cible (« → `<label> — main` » ou « → `<label> — <tab>` »), avec
  son dot, modifiable par « Changer de cible » : une section par
  workspace, son `main` (dot comme dans la grille, badge « en
  attente ») puis, en retrait, ses tabs ciblables (§4.2) avec le dot
  et le badge de leur Claude
- l'état de la cible et le prochain envoi (§4.1)
- cible tab seulement : case « Envoyer /clear avant », décochée à
  l'ouverture et à chaque changement de tab
- tab ciblé disparu de herdr pendant l'aperçu : « Ce tab n'existe
  plus : choisis une autre cible. », « Envoyer » désactivé ; jamais de
  repli silencieux sur le `main`
- le texte, éditable, placeholder « Que doit faire l'agent ? » ;
  clavier ouvert pour Écrire, pré-rempli pour Coller et la dictée
- l'origine : « Écrit », « Collé », « Dictée nettoyée », ou
  « Transcription brute : <raison> » ; dès qu'une salve a été dictée,
  l'origine est la dictée, même si le texte vient d'Écrire ou Coller ;
  « Transcription brute » l'emporte si une salve n'a pas été nettoyée,
  avec la raison de la dernière ; « Voir l'original » dès qu'une salve
  a été nettoyée, il montre la transcription brute de chaque salve,
  séparées par un trait
- les captures jointes, sous le texte dans le même cadre : vignettes
  au format de l'image, aux coins arrondis, dans l'ordre d'ajout, chacune
  avec une croix « Retirer la capture <n> » ; rien quand il n'y en a
  pas
- « Joindre des captures », bouton à icône seule entre l'origine et
  « Dicter la suite », ouvre le sélecteur de photos du système (images
  seulement, sans demande d'accès à la photothèque) ; trois captures
  au plus par demande, le bouton est désactivé une fois les trois
  jointes. Chaque image est réduite à 1568 px sur son plus grand côté
  et convertie en JPEG ; pendant ce temps, une vignette d'attente tient
  sa place dans l'ordre de sélection et « Envoyer » est désactivé, pour
  qu'aucune capture ne manque à l'envoi. Sa croix la retire, seule
  issue quand une photo iCloud ne se télécharge pas ; les autres
  captures ne l'attendent pas. Image illisible : « Une
  image n'a pas pu être lue. » au-dessus d'« Envoyer »
- « Dicter » (texte vide) ou « Dicter la suite » ouvre l'écran de
  dictée (§5.1), quelle que soit l'origine ; la salve nettoyée s'ajoute
  à la fin du texte, après un retour à la ligne, sans toucher au texte
  déjà là, corrigé ou non
- « Envoyer », désactivé tant que le texte est vide ou pendant
  l'envoi, même avec des captures : une image seule ne dit pas quoi
  en faire ; vers un tab sans Claude, l'envoi échoue avant le Mac :
  « Plus de Claude dans <label> — <tab> : relance-le sur le Mac. » ; en cas d'échec, l'erreur s'affiche au-dessus et l'aperçu
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
- chaque remplacement retenu range l'entendu comme variante
  « apprise » du terme voulu, créé s'il manque (identifié sans tenir
  compte de la casse ni des accents, il garde son orthographe d'origine) ;
  un entendu n'appartient qu'à un terme : déjà connu, il passe au
  dernier terme voulu et remonte en tête, avec son compteur augmenté
  s'il garde le même terme. Remettre dans l'aperçu une variante à la
  place de son terme (« Acme » → « ack me ») retire cette
  variante du terme au lieu d'apprendre l'inverse, y compris quand le
  mot voisin a été retenu (« GitHub demain » → « guithub demain »). Un terme appris qui
  n'a plus de variante
  disparaît ; au-delà de 200 termes, les moins récents sont oubliés.
  Le lexique se consulte et se corrige dans les Réglages (§4.5)
- le lexique est gardé sur l'iPhone, dans un fichier JSON versionné
  (`dictation-lexicon.json`, Application Support) :

  ```json
  {
    "terms" : [
      {
        "source" : "typed",
        "text" : "Acme",
        "updatedAt" : "2026-10-12T09:00:00Z",
        "variants" : [
          { "count" : 2, "heard" : "ack me", "source" : "learned", "updatedAt" : "2026-10-12T09:00:00Z" }
        ]
      }
    ],
    "version" : 1
  }
  ```

  `source` vaut `typed` (saisi) ou `learned` (appris), une valeur
  inconnue est lue comme `learned` ; tout autre champ est ignoré ; un
  fichier d'une version supérieure n'est pas lu. Les corrections de
  l'ancien lexique (UserDefaults) sont reprises une fois : chaque voulu
  devient un terme appris, chaque entendu une de ses variantes apprises
- sauvegarde sur le Mac (`lexicon-put`, §8.2), sans jamais que la
  dictée ne lise le Mac : après chaque changement (2 s après le
  dernier) et à chaque rafraîchissement réussi (§3), tant que le
  dernier changement n'est pas sauvegardé, le lexique entier est
  écrit, en tâche de fond. Un échec ne s'affiche pas : il est retenté
  au rafraîchissement suivant, et la liste (§4.5) dit que la
  sauvegarde attend. La sauvegarde du Mac est écrasée, jamais
  fusionnée : une modification faite sur le Mac est perdue
- restauration, seulement juste après un appairage (§2) avec un
  lexique vide sur l'iPhone, typiquement après une réinstallation :
  l'app lit la sauvegarde (`lexicon-get`) avant toute écriture, la
  reprend telle quelle (un terme appris entre-temps sur l'iPhone
  l'emporte sur celui du Mac) et l'annonce : « Lexique restauré depuis
  le Mac », « <n> termes repris de la sauvegarde. ». Tant que la
  lecture échoue, rien n'est écrit sur le Mac et elle est retentée à
  chaque rafraîchissement, même après une relance. Sauvegarde absente,
  vide ou illisible : rien n'est repris. Appairage avec un lexique non
  vide : la sauvegarde n'est pas lue, elle est écrasée
- journal des dictées, pour mesurer le lexique en usage réel, sans
  rien afficher : chaque envoi réussi d'une dictée (pas d'un texte
  écrit ou collé) ajoute une entrée au journal de l'iPhone
  (`dictation-journal.jsonl`, Application Support), une ligne JSON par
  envoi :

  ```json
  {"id":"5B1F…","salves":[{"edited":"Lance Acme et le GitHub.","hints":[{"applied":true,"heard":"guithub","term":"git hub"}],"previewed":"Lance Acme et le git hub.","proposed":"Lance Acme et le git hub.","raw":"lance ack me et le guithub","replaced":"lance Acme et le guithub","replacements":[{"heard":"ack me","term":"Acme"}]}],"sent":"Lance Acme et le GitHub.","sentAt":"2026-10-12T09:00:00Z","version":1}
  ```

  - une salve par dictée, dans l'ordre : `raw` la transcription brute,
    `replaced` après le remplacement par le code d'avant le nettoyage,
    `replacements` chaque remplacement fait par le code avant et après
    le nettoyage (le texte entendu tel qu'écrit, le terme), `hints` les
    variantes signalées au nettoyage, `applied` vrai quand la sortie du
    modèle n'a plus l'entendu et contient le terme (faux sans
    nettoyage), `proposed` le texte de la salve, `reason` la raison
    d'une transcription brute gardée (absent si nettoyée), `previewed`
    tout le texte de l'aperçu juste après la salve et `edited` ce qu'il
    était devenu avant la salve suivante, ou à l'envoi pour la dernière
    (les textes comparés par l'apprentissage)
  - `sent` le texte envoyé, `sentAt` l'heure de l'envoi, `id` unique
  - une ligne d'une version supérieure, ou un champ inconnu, est à
    ignorer par qui lit le journal
  - les entrées en attente partent sur le Mac (`journal-append`, §8.2)
    juste après l'envoi et à chaque rafraîchissement réussi (§3), en
    tâche de fond ; elles ne quittent l'iPhone qu'une fois reçues. Un
    échec ne s'affiche pas, il est retenté au rafraîchissement suivant,
    même après une relance. Au-delà de 500 entrées en attente, les plus
    anciennes sont oubliées
  - le journal ne quitte jamais l'iPhone et le Mac appairé : le
    fichier en attente est exclu de la sauvegarde iCloud
  - l'entrée garde le texte tel qu'au moment où on a tapé Envoyer,
    même s'il est modifié pendant l'envoi

## 6. Ce que fait un envoi

Cible : l'agent herdr `<slug>-main` dans le tab 1 du workspace. Un
envoi vers un tab suit §6.3.

1. agent absent : split d'un pane du tab 1 (cwd de ce pane) et
   lancement de Claude en yolo mode, nom Remote Control `<label>—main`
   (`~` devient `home`)
2. agent `idle` ou `done` : `/clear`, puis le prompt enveloppé
3. agent `working` ou `blocked` : l'envoi attend sur le Mac et part dès
   qu'il redevient `idle` ou `done`
4. plusieurs envois vers un même agent partent dans l'ordre, chacun
   précédé de son `/clear` ; le suivant attend que Claude ait commencé
   puis fini le précédent
5. un agent du même nom dans un autre workspace n'est jamais visé :
   l'envoi échoue

Notice après l'envoi (5 s, fermée au tap) :

| Agent au moment de l'envoi | Notice |
| --- | --- |
| absent | Envoyé à <label> — Le Mac lance Claude dans le tab 1, nommé <agent>, puis lui transmet la demande. |
| `idle` ou `done` | Envoyé à <label> — Le Mac vide le contexte de Claude, puis lui transmet la demande. |
| autre, ou envoi déjà en file | En file pour <label> — Claude est occupé : la demande partira dès qu'il aura fini. |

Vers un tab, `<label>` devient `<label> — <tab>`, et un Claude `idle`
ou `done` sans « Envoyer /clear avant » donne « Envoyé à <label> — <tab>
— Le Mac transmet la demande telle quelle à Claude, qui garde son
contexte. »

Un envoi suivi par l'app qui passe `failed` affiche « Échec de l'envoi
vers <label> » (`<label> — <tab>` pour un tab) avec sa raison, une
seule fois.

Avec des captures, l'app les pose d'abord sur le Mac (`attach`, §8.2),
une par une, puis crée le job ; la demande les cite par leur chemin
après le texte :

```text
<texte>

Captures d'écran jointes, à lire avec Read :
- <chemin sur le Mac>
```

Ce bloc fait partie de `<texte>` dans les consignes (§6.1 à §6.3). Une
capture refusée par le Mac fait échouer l'envoi avant la création du
job ; les captures déjà posées restent dans l'historique et repartent
avec « Renvoyer ».

Chaque envoi est enregistré sur l'iPhone dès qu'on tape Envoyer, avant
la connexion au Mac : le texte tel que saisi (sans la consigne), le
workspace, le tab et le choix de `/clear` pour un envoi vers un tab, la
date, et les chemins des captures une fois posées sur le Mac. Son statut :

| Moment | Statut |
| --- | --- |
| le Mac n'a pas encore répondu | Envoi… |
| job créé, `queued` ou `sending` | En file |
| job `sent` | Envoyé |
| échec avant le Mac, ou job `failed` | Échec, avec la raison |
| encore « Envoi… » au lancement de l'app (crash pendant l'envoi) | Échec, « Envoi interrompu avant la réponse du Mac. » |

Un job purgé par le Mac laisse l'envoi à son dernier statut. Seuls les
20 envois sans réponse les plus récents sont gardés, et à part les 20
questions répondues les plus récentes : une réponse fait passer son
envoi des uns aux autres.

### 6.1 Consigne standard

```text
Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale :
attention aux erreurs de transcription).

<texte>

Consignes :
- explore le code pour comprendre la demande, ne modifie rien ici
- si la demande est ambiguë, pose tes questions avec AskUserQuestion
- si c'est une simple question, sans travail à faire : réponds sans
  /start avec `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" answer
  <job_id>`, sur l'entrée standard un résumé d'une phrase, une ligne
  vide puis la réponse complète en markdown
- sinon, termine obligatoirement en dispatchant le travail avec /start
```

`<job_id>` est écrit `{{job_id}}` par l'app et remplacé par l'id du job
quand `dispatch.sh` le crée (§8.2).

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
- si c'est une simple question, sans travail à faire : réponds-y
  toi-même, sans relais ni /start, en explorant ce qu'il faut (le
  projet visé compris), puis remets ta réponse avec
  `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" answer <job_id>`,
  sur l'entrée standard un résumé d'une phrase, une ligne vide puis la
  réponse complète en markdown
- sinon, identifie le projet visé parmi les workspaces herdr ouverts :
  labels avec `herdr workspace list`, dossiers avec
  `herdr pane list --workspace <workspace_id>` (cwd)
- si plusieurs projets peuvent correspondre, pose la question avec
  AskUserQuestion avant tout relais
- si un projet est visé, relaie-lui la demande puis arrête-toi, sans
  /start : `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" relay
  <workspace_id>` avec sur l'entrée standard la demande d'origine,
  corrigée des erreurs de transcription évidentes, complétée des
  réponses à tes questions et suivie des chemins des captures jointes
  s'il y en a
- si aucun projet ouvert n'est concerné : explore ce qu'il faut pour
  comprendre la demande, pose tes questions avec AskUserQuestion si
  elle est ambiguë et termine obligatoirement en dispatchant le
  travail avec /start
```

Le relais suit le même chemin qu'un envoi de l'app vers ce workspace
(même nom d'agent, création, file, `/clear`, consigne standard) et
s'affiche sur la ligne du projet. Un relais vers Home ou vers un
workspace inconnu est refusé.

### 6.3 Envoi vers un tab

Cible : le premier Claude du tab choisi (§4.2), désigné par son
`pane_id`, sans nom herdr (les Claude lancés par /start n'en ont pas).

1. le texte part précédé du seul avertissement de dictée, sans
   consigne standard (§6.1) ni consigne de Home (§6.2), réservées au
   `main` :

   ```text
   Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale :
   attention aux erreurs de transcription).

   <texte>
   ```
2. `/clear` avant le texte seulement si « Envoyer /clear avant » est
   coché
3. Claude `working` ou `blocked` : même file que pour le `main`,
   l'envoi attend `idle` ou `done`, ordre conservé
4. jamais de lancement de Claude : un pane qui n'héberge plus de
   Claude, qui appartient à un autre workspace ou dont le Claude porte
   un nom herdr (un `-main` déplacé, qui a sa propre file) fait échouer
   l'envoi ; vérifié à la prise du job et juste avant d'envoyer, après
   l'attente

### 6.4 Nommage

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

### 6.5 Réponse à une simple question

C'est le `-main` qui décide, d'après la consigne (§6.1, §6.2), qu'une
demande est une simple question : l'app ne propose aucun choix.

1. il explore sans rien modifier, sans /start, et remet sa réponse par
   `dispatch.sh answer <job_id>` : première ligne le résumé, puis la
   réponse complète en markdown
2. le Mac garde la réponse avec le job et pousse une notif (§7)
3. l'envoi passe dans « Questions » (§4.4) dès que l'app la récupère :
   au tap sur la notif, ou au rafraîchissement qui voit le job répondu
   dans `status`, notif ratée comprise
4. un relais de Home (§6.2) crée un job que l'app ne suit pas : si le
   `-main` du projet y répond quand même, la notif ouvre la réponse,
   que l'historique ne garde pas
5. un envoi vers un tab (§6.3) n'a pas de consigne, donc pas de réponse
   de ce type

Feuille de réponse, ouverte du bas, sans bouton Fermer (on la glisse
vers le bas), moitié puis plein écran : titre = label de l'envoi, la
question en secondaire, le résumé en titre, puis la réponse complète
(markdown : titres, listes, blocs de code, gras, italique, code et liens
en ligne), sélectionnable. « Copier » copie la réponse complète. Pendant
qu'elle arrive du Mac, le résumé de la notif s'affiche seul avec un
indicateur ; Mac injoignable : « Réponse complète indisponible :
<raison> » sous le résumé. La feuille ferme l'historique et les réglages
s'ils sont ouverts.

## 7. Notifications

- autorisation demandée au premier rafraîchissement réussi, une fois
  par lancement ; accordée, l'app envoie son token au Mac
  (`register-push`) à chaque lancement
- échec de cet envoi : notice « Notifications non installées sur le
  Mac » ; échec de l'enregistrement APNs : « Notifications
  indisponibles »
- une notif part quand un agent `-main` passe `blocked` et le reste
  3 s, une fois par question ; jamais pour les Claude des worktrees.
  Titre : label du workspace, sous-titre : agent, corps : ce que
  montre l'écran de l'agent, tronqué à 178 caractères (« … ») :
  - question d'une AskUserQuestion
  - permission Bash : « Veut lancer : <description> », ou « Veut
    lancer une commande » sans description, jamais la commande brute
  - permission sur un fichier : « Veut modifier : <fichier> »
    (édition, écrasement) ou « Veut créer : <fichier> »
  - autre permission : « Demande d'autorisation : <titre de la
    demande> »
  - rien de reconnu : « Attend une réponse »
- une notif part quand un `-main` remet sa réponse à une simple
  question (§6.5) : titre = label de l'envoi, sous-titre « Réponse »,
  corps = résumé, tronqué à 178 caractères (« … ») ; tap : la feuille
  de réponse, jamais l'app Claude. Sans iPhone enregistré, la réponse
  est gardée sans notif
- notif reçue app ouverte : bannière, liste et son
- tap : le workspace de l'agent devient la cible, puis la session
  s'ouvre dans l'app Claude. Si le lien manque ou que l'app Claude ne
  le prend pas : carte « <agent> attend une réponse », « La session ne
  s'est pas ouverte dans Claude. », bouton « Ouvrir dans Claude »

## 8. Contrat avec le Mac

L'app ne parle au Mac que par SSH, et ce contrat change en même temps
des deux côtés : le script est réinstallé par l'app avant chaque
`enqueue`, `register-push`, `lexicon-get`, `lexicon-put` et
`journal-append`, le hook
avec `register-push`. `status`
lit le script déjà installé, qui peut venir d'une version précédente
de l'app : sa sortie reste lisible par l'app plus récente.

### 8.1 API herdr (`herdr.sock`)

- `workspace.list` : `workspace_id`, `number`, `label` ; son
  `agent_status`, agrégé sur tous les tabs, n'est pas lu
- `agent.list` : `name` (absent pour un Claude lancé à la main ou par
  /start), `agent` (`claude` pour un Claude), `pane_id`,
  `workspace_id`, `tab_id`, `agent_status`
- `tab.list` sans paramètre : `tab_id`, `workspace_id`, `number`,
  `label` ; son `agent_status` n'est pas lu. Échec de cet appel : la
  dernière liste reçue est gardée (aucun tab avant la première), le
  reste de l'écran est inchangé
- tolérance : tout autre champ est ignoré, un `agent_status` inconnu
  devient « État inconnu »

### 8.2 `dispatch.sh`

| Commande | Entrée standard | Sortie |
| --- | --- | --- |
| `install` | le script | rien |
| `enqueue <workspace_id> <agent> <label_base64>` | prompt enveloppé | id du job |
| `enqueue-pane <workspace_id> <pane_id> <clear\|keep>` | texte brut | id du job ; code 2 pour un `pane_id` hors `[A-Za-z0-9]+:[A-Za-z0-9]+` ou une option inconnue |
| `relay <workspace_id>` | demande brute | id du job ; code 2 vers Home ou un workspace inconnu |
| `attach <jpg\|png>` | une image | chemin absolu du fichier gardé sur le Mac ; code 2 pour une image vide, de plus de 20 Mo, ou une autre extension ; code 1 sans chemin quand le Mac ne peut pas l'écrire |
| `answer <job_id>` | résumé sur la première ligne, ligne vide, réponse complète | rien ; code 2 pour un job inconnu ou une première ligne vide ; notif refusée : réponse gardée, raison sur stderr, code 0 |
| `read-answer <job_id>` | rien | la réponse telle que remise ; code 2 sans réponse |
| `status` | rien | une ligne par job : `id`, `workspace_id`, `agent`, `state`, `error`, `answered` (vide sans réponse), séparés par des tabulations |
| `register-push <token> <sandbox\|production> <topic> <team_id>` | le hook | rien |
| `lexicon-get` | rien | la sauvegarde du lexique telle qu'écrite, rien sans sauvegarde (code 0) |
| `lexicon-put` | le lexique (JSON de §5.2) | rien ; code 2 pour une entrée sans `version` entière lisible, sauvegarde précédente intacte |
| `journal-append` | entrées du journal des dictées (§5.2), une ligne JSON chacune | rien ; code 2 pour une entrée vide, qui n'est pas un objet JSON, sans `version` entière ou sans `id` en `[A-Za-z0-9-]{1,64}`, journal intact et rien ajouté de l'envoi ; code 1 quand le journal ne peut pas être écrit ou reste pris par un autre ajout plus de 10 s |

- `agent` : nom de l'agent, ou `pane_id` pour un envoi vers un tab
  (une app plus ancienne le compte dans le workspace)
- `state` : `queued`, `sending`, `sent`, `failed` ; l'app ignore une
  ligne d'état inconnu
- `error` : sur une ligne, tabulations et retours remplacés par des
  espaces
- `answered` : absent d'un script plus ancien, l'app lit alors le job
  sans réponse
- `{{job_id}}` dans le prompt d'`enqueue` ou de `relay` devient l'id du
  job
- les jobs `sent` disparaissent après une heure, les `failed` après un
  jour, ceux qui ont une réponse sept jours après elle
- les images d'`attach` vivent sous
  `~/.local/state/heraldr/attachments/` et disparaissent après une
  semaine, indépendamment des jobs : un envoi peut attendre dans la
  file, et le Claude qui reçoit la demande peut la confier par /start
  à une autre session qui les lira plus tard
- `register-push` refuse un token hors `[0-9a-f]{64,200}`, une équipe
  hors `[A-Z0-9]{10}`
- le lexique est sauvegardé dans `~/.config/heraldr/lexique.json`,
  écrit dans un fichier temporaire puis renommé ; le script n'en lit
  que `version` et le rend octet pour octet
- le journal des dictées s'ajoute à `~/.config/heraldr/journal-dictees.jsonl`,
  dans l'ordre reçu, ligne pour ligne ; une entrée dont l'`id` est déjà
  dans le journal est ignorée, pour qu'un envoi répété après une
  coupure ne la double pas. Les entrées retenues sont ajoutées à la
  fin, sans réécrire l'existant, un ajout à la fois (verrou), après un
  retour à la ligne si la dernière ligne n'en a pas. Il n'est ni lu
  par l'app ni purgé : on le vide à la main

### 8.3 Payload des notifications

Question : `aps.alert` (`title`, `subtitle`, `body`), `workspace_id`,
`agent` et `session_url` facultatif. Sans `workspace_id` ou `agent`, le
tap est ignoré.

Réponse : `aps.alert`, `kind` = `answer`, `job_id`, `workspace_id`,
`agent`. Sans `kind` = `answer` ou `job_id`, la notif se lit comme une
question.

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
- réponse à une simple question envoyée vers un tab
- détail par agent
- multi-machines, sessions herdr nommées
