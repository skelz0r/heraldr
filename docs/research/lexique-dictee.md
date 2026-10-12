# Veille : lexique de dictée

Veille du 2026-10-12, sans implémentation. Question de départ : les
corrections de dictée ne sont pas précises ; le lexique, gardé
aujourd'hui sur l'iPhone, serait-il mieux tenu sur le Mac dans une vraie
base ? Ce document dit ce que font les autres, ce qui cloche chez nous
et propose un ordre d'itération. Rien n'y est décidé : une décision
prise ira dans `docs/decisions.md`, un changement de comportement dans
`docs/spec.md`.

L'existant (spec §4.5, §5.1, §5.2) n'est pas redécrit ici.

## Conclusion

Le stockage n'est pas en cause. Le problème vient de trois points :

- le vocabulaire contextuel est ignoré par le transcripteur qu'on utilise ;
- la liste de paires donnée au petit modèle va à l'encontre des consignes d'Apple ;
- l'apprentissage silencieux n'est pas filtré.

Une base SQLite sur le Mac ne corrigerait rien de cela, et la lire à
chaque dictée ajouterait une dépendance réseau : à écarter. Le Mac a en
revanche sa place comme miroir, pour ne rien perdre à une
réinstallation et pour éditer la liste au clavier.

Reco :

- organiser le lexique en termes (« Acme ») portant leurs
  variantes entendues (« ack me ») ;
- utiliser les termes pour biaiser la reconnaissance, et faire
  remplacer les variantes connues par le code, pas par le modèle ;
- remplacer l'apprentissage silencieux par des suggestions à valider ;
- garder la copie de l'iPhone pour dicter, avec un miroir JSON sur le
  Mac synchronisé par SSH à chaque connexion ;
- sortir la liste des Réglages vers une page dédiée.

## Ce qui cloche chez nous

### 1. Le vocabulaire contextuel ne sert à rien aujourd'hui

`Dictation.swift` utilise `SpeechTranscriber` quand il est disponible,
donc presque toujours, et lui passe les « voulu » en
`contextualStrings[.general]`. Or seul `DictationTranscriber` en tient
compte :

- doc d'`AnalysisContext.contextualStrings` : la propriété n'est décrite
  qu'« avec le module DictationTranscriber »
  (<https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings>) ;
- réponses sur les forums Apple, septembre 2025 et janvier 2026 : « The
  SpeechTranscriber module does not currently take contextual strings
  into account »
  (<https://developer.apple.com/forums/thread/801877>,
  <https://developer.apple.com/forums/thread/811083>). Le compte qui
  répond n'est pas formellement identifié comme Apple, mais la doc va
  dans le même sens ;
- un test A/B publié sur le même audio donne le nom « Ibiuna » reconnu
  5 fois sur 5 avec le biais sous `DictationTranscriber`, 0 sur 5 sans
  (<https://github.com/augustomklee/mach-voice/pull/2>) ;
- article « iOS 26 didn't kill custom vocabulary, you're adding it to the
  wrong module »
  (<https://dev.to/simple_memo/ios-26-didnt-kill-custom-vocabulary-youre-adding-it-to-the-wrong-module-5bdc>).

L'appel est fait avec `try? await analyzer.setContext(context)` : un
refus passerait sans bruit. Il faut vérifier sur l'iPhone si
`setContext` lève une erreur ou accepte et ignore.

Le choix n'est pas gratuit. `SpeechTranscriber` est un modèle neuf,
`DictationTranscriber` reprend le modèle de la dictée système (WWDC25
session 277, <https://developer.apple.com/videos/play/wwdc2025/277/>).
L'un est plus précis en général, l'autre est le seul qu'on peut
biaiser. Les comparatifs publiés ne portent que sur l'anglais
(MacStories :
<https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/>).
Pour le français mêlé d'anglais technique, rien n'est publié : il faut
mesurer.

`DictationTranscriber` accepte en plus un modèle de langue
personnalisé, via le content hint `customizedLanguage(modelConfiguration:)`
et `SFCustomLanguageModelData`
(<https://developer.apple.com/documentation/speech/dictationtranscriber/contenthint/customizedlanguage(modelconfiguration:)>,
<https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata>).
Ce modèle permet :

- des phrases pondérées ;
- des gabarits (« crée une branche <terme> ») ;
- des prononciations en X-SAMPA pour les mots inventés comme `herdr` ou
  `worktree`.

Apple prévient que pour ces mots inventés, sans prononciation, le
système « may not estimate their pronunciation correctly ». Le support
de `fr_FR` est à vérifier avec `supportedPhonemes(locale:)`. Le modèle
se construit en un temps non négligeable (WWDC23 session 10101,
<https://wwdcnotes.com/documentation/wwdc23-10101-customize-ondevice-speech-recognition/>).

Limites documentées des contextual strings : 100 phrases au plus,
d'un ou deux mots de préférence.

### 2. La consigne du nettoyage demande au modèle ce qu'il fait mal

Le nettoyage passe 20 paires « entendu → voulu », à corriger « quand le
contexte s'y prête ». Pour le modèle on-device (~3 milliards de
paramètres, contexte de 4096 tokens), cela fait 20 règles
conditionnelles, dont presque aucune ne concerne la dictée en cours.
Apple dit exactement de ne pas faire ça :

- « too much conditional complexity can affect the on-device model's
  ability to follow instructions » ; préférer « programming logic to
  customize the prompt based on known information »
  (<https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model>) ;
- le modèle donne le meilleur de lui-même sur « a single specific
  task » et n'est pas optimisé pour le code (WWDC25 session 248,
  <https://developer.apple.com/videos/play/wwdc2025/248/>) ;
- des consignes longues dégradent la qualité (TN3193,
  <https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window>).

Côté recherche, la correction par LLM sur le texte seul fait des
changements inutiles et gère mal les mots rares, sauf si on lui donne
le contexte phonétique ou des hypothèses alternatives
(<https://arxiv.org/abs/2505.17410>). Les approches qui marchent
contraignent le modèle et vérifient ses éditions par du code
(RECOVER, <https://arxiv.org/abs/2603.16411>), ou ne corrigent que les
passages incertains (<https://arxiv.org/abs/2310.11532>).

Les produits du marché font le même constat. Wispr Flow le résume :
« LLMs are phenomenal at recall, but very low precision »
(<https://wisprflow.ai/post/technical-challenges>). Sa doc conseille
d'ajouter une correction explicite quand un mot du dictionnaire ne
suffit pas
(<https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary>).
FreeFlow passe le vocabulaire au LLM et « Claude Code » reste mal écrit
(<https://github.com/zachlatta/freeflow/issues/125>). VoiceInk a vu
son LLM forcer un terme du dictionnaire là où il ne fallait pas
(<https://github.com/Beingpax/VoiceInk/issues/281>).

L'hypothèse de départ, « le petit modèle on-device applique mal des
paires listées dans une consigne », est donc confirmée par les
consignes d'Apple, la recherche et les produits. Il n'existe pas de
mesure publiée sur un modèle de 3B appliquant une liste de corrections.

### 3. L'apprentissage retient du bruit

Le diff à l'envoi ne distingue pas une erreur d'écoute d'une
reformulation : changer « regarde » en « vérifie » produit une paire.
La littérature le dit depuis longtemps : « if the learning module
blindly learns from all the edits the user has made, it will gradually
corrupt the ASR system »
(Yu et al., Interspeech 2004,
<https://www.isca-archive.org/interspeech_2004/yu04f_interspeech.pdf>).
Les brevets Google filtrent les éditions par distance d'édition,
similarité phonétique et répétition
(<https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12340799>).

Ce qui aggrave chez nous :

- aucun filtre de proximité phonétique entre entendu et voulu, seul le
  seuil de « moitié des mots changés » ;
- une seule occurrence suffit, et elle remonte en tête ;
- le classement se fait par récence, alors que `count` est stocké mais
  ne sert à rien. Les 20 paires de la consigne sont donc les 20
  dernières, pas les 20 qui servent ;
- le mot voisin gardé (« on push → git push ») rend la paire plus sûre
  pour un remplacement, mais plus rare à revoir telle quelle ;
- une paire supprimée peut être réapprise dès l'envoi suivant.

Le reste du marché fait ainsi :

| Produit | Apprentissage |
| --- | --- |
| OpenWhispr | silencieux, avec annulation ; a pollué la liste (<https://github.com/OpenWhispr/openwhispr/issues/358>), ce qui a entraîné l'ajout d'un interrupteur ; 28 des 29 mots d'un utilisateur venaient de l'auto-apprentissage quand son prompt a tronqué ses dictées (<https://github.com/OpenWhispr/openwhispr/issues/2474>) |
| Wispr Flow | n'apprend que les changements d'orthographe d'un mot (noms propres, termes de métier, acronymes) ; exclut le code, les chemins, les URL, les nombres et les mots courants ; n'en réapprend jamais un supprimé (doc dictionnaire et <https://wisprflow.ai/data-controls>) |
| VoiceInk | fait juger chaque édition par un LLM (« preuve phonétique », pas de réécriture sémantique), puis vérifie le verdict par du code (<https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/AutoLearn/AutoLearnAIReviewer.swift>) ; le mainteneur admet que ça « needs more polishing » (<https://github.com/Beingpax/VoiceInk/issues/985>) |
| FluidVoice | modèle le plus prudent : un mot seul, flexions rejetées, suggestion affichée après 1 à 3 occurrences en 7 jours (réglable), 7 jours de pause après un refus, plus aucune suggestion après 3 refus dans la session (<https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/AutomaticDictionaryCorrectionTracker.swift>) |

L'hypothèse « le diff capte des reformulations autant que des erreurs
d'écoute » n'est pas mesurée chez nous, mais tout le monde a dû filtrer.

### 4. 50 / 20 entrées : le problème n'est pas le nombre

Les listes de biais servies par les fournisseurs vont de 20 à 100
termes. Au-delà, les mots proches se déclenchent à tort :

| Source | Recommandation ou constat |
| --- | --- |
| Deepgram | jusqu'à 100 termes, conseille « 20-50 » (<https://developers.deepgram.com/docs/keyterm>) |
| Google | prévient que plus de boost veut dire plus de faux positifs (<https://docs.cloud.google.com/speech-to-text/docs/boost>) |
| TCPGen | les gains sur les mots biaisés sont mangés par les erreurs sur les autres (<https://arxiv.org/abs/2109.00627>) |
| FluidVoice | une grosse liste importée a corrompu des mots justes (<https://github.com/altic-dev/FluidVoice/issues/944>) |

Le bon nombre dépend du canal :

- pour la reconnaissance, ≤ 100 termes choisis ;
- pour le modèle, 0 à 3 paires pertinentes pour la dictée en cours ;
- pour le remplacement par le code, autant qu'on veut, puisque seule
  une correspondance déclenche.

Garder plus de 50 corrections ne coûte rien si on ne les donne pas
toutes au modèle.

## Ce que font les autres

### Deux sortes d'entrées, trois canaux

Tous les produits mûrs finissent avec deux listes :

- des **termes**, c'est-à-dire l'orthographe voulue, envoyés comme
  indices à la reconnaissance ;
- des **remplacements** entendu → voulu, appliqués par du code.

| Produit | Termes (indices) | Remplacements (code) | LLM |
| --- | --- | --- | --- |
| Wispr Flow (fermé) | dictionnaire, injection non documentée | « Correct a misspelling » : mot entier, insensible à la casse, plus long d'abord, casse gardée ([doc](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)) | pas pour les prompts libres |
| Superwhisper (fermé) | « Vocabulary », « keep the list short » ; cause d'hallucinations si trop long ([doc](https://superwhisper.com/docs/get-started/interface-vocabulary), [hallucinations](https://superwhisper.com/docs/common-issues/hallucinations)) | « Replacements », « applied programmatically, with no AI interpretation » | selon le mode |
| Aqua Voice (fermé) | dictionnaire ; correspondance « by how they sound » en japonais depuis le 2026-10-06 ([changelog](https://aquavoice.com/changelog)) | snippets, « Preserve case » | consignes libres |
| MacWhisper (fermé) | mots corrigés seulement quand un prompt IA est actif ([notes de version](https://macwhisper-site.vercel.app/release_notes.html), miroir non officiel) | « Global Replace » sensible ou non à la casse ([doc](https://docs.macwhisper.com/article/37-find-and-replace-in-transcriptions)) | oui |
| VoiceInk (Swift, ouvert) | keyterms des API cloud ; retiré du prompt Whisper ([#250](https://github.com/Beingpax/VoiceInk/issues/250)) | regex à frontières Unicode, plus long d'abord, variantes séparées par des virgules ([WordReplacementService.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/Workflows/WordReplacementService.swift)) | « Do not force a replacement when the text clearly means something else » ([AIEnhancementService.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift#L152-L165)) |
| FluidVoice (Swift, ouvert) | boosting CTC Parakeet, 256 termes max ([ParakeetVocabularyStore.swift](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ParakeetVocabularyStore.swift)) | regex, plus long d'abord, garde contre la ré-expansion ([ASRService.swift](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ASRService.swift#L7479-L7531)) | pas de dictionnaire |
| OpenWhispr (Electron, ouvert) | `initial_prompt` Whisper et keyterms ; plafonds par fournisseur ([dictionaryPromptCap.js](https://github.com/OpenWhispr/openwhispr/blob/main/src/utils/dictionaryPromptCap.js)) | snippets seulement | liste ajoutée sans plafond |
| Handy (Rust, ouvert) | `initial_prompt` pour Whisper | correspondance floue Levenshtein × Soundex, ASCII seulement ([text.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/audio_toolkit/text.rs#L79-L235)) | non |

Leçons tirées des tickets :

- **Prompt Whisper** : le canal le plus fragile. Chez OpenWhispr, un
  silence renvoie tout le dictionnaire ([#842](https://github.com/OpenWhispr/openwhispr/issues/842)),
  le texte du prompt est répété ([#2581](https://github.com/OpenWhispr/openwhispr/issues/2581)),
  une dictée longue est tronquée ([#2474](https://github.com/OpenWhispr/openwhispr/issues/2474)).
  Sans objet chez nous, mais c'est l'équivalent de trop charger le
  biais.
- **Remplacement par le code** : le canal le plus fiable, à condition
  de le faire bien :
  - frontières de mot Unicode, pas `\b` ASCII : VoiceInk a remplacé
    dans « vergrößern » ([#756](https://github.com/Beingpax/VoiceInk/issues/756)) ;
  - plus long d'abord ;
  - détection des cycles ;
  - autoriser les corrections de casse seule, `iphone → iPhone`
    ([#961](https://github.com/Beingpax/VoiceInk/issues/961)).
- **Faux positifs du remplacement**, la raison de notre refus initial :
  ils viennent des entendus courts et courants. Chez FluidVoice,
  `sean → Shaun` a aussi changé « mean »
  ([#880](https://github.com/altic-dev/FluidVoice/issues/880)), parce
  que le boosting tirait vers des mots proches. Chez Handy, le Soundex
  tronqué faisait de « Son of » « Shinobi »
  ([#1333](https://github.com/cjpais/Handy/issues/1333),
  [#2099](https://github.com/cjpais/Handy/pull/2099)). Un remplacement
  exact multi-mots, comme notre « on push → git push », n'a pas ce
  problème.
- **Correspondance phonétique codée** : faible partout. Les algorithmes
  français (Phonex, Soundex2, FONEM,
  <https://abydos.readthedocs.io/en/latest/_modules/abydos/phonetic/_fonem.html>)
  sont faits pour des noms de famille. Aucun ne modélise de l'anglais
  prononcé à la française (« ouorktri » → worktree). C'est utile pour
  filtrer ou choisir des candidats, pas pour remplacer sans contrôle.

### Wispr Flow en détail

Référence du marché, fermé, transcription toujours dans le cloud
(<https://wisprflow.ai/data-controls>) :

- **Modèle** : un mot seul, ou une paire « Correct a misspelling ». Les
  snippets (déclencheur parlé → bloc de texte) et les styles par
  catégorie d'app sont à part. Les styles ne s'appliquent qu'en anglais
  (<https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles>).
- **Ajout** :
  - à la main ;
  - depuis l'historique (« Add to vocabulary → Correct a misspelling ») ;
  - import CSV, 1 000 entrées par fichier
    (<https://docs.wisprflow.ai/articles/8955301725-how-do-i-bulk-import-for-dictionary-and-snippets>) ;
  - partage en équipe ;
  - « Auto-add to Dictionary », qui surveille le champ où le texte a
    été collé et retient un changement d'orthographe, sans confirmation
    documentée.
- **Priorité** : depuis le 2026-03-31, on peut mettre une étoile sur un
  mot pour qu'il soit prioritaire à la transcription, et la liste est
  classée par usage (<https://wisprflow.ai/whats-new>). Cela laisse
  penser que la liste envoyée à la reconnaissance est limitée ; c'est
  une déduction.
- **Contexte** : catégorie de l'app, texte autour du curseur, noms à
  l'écran, noms de variables et de fichiers dans les éditeurs de code
  (<https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness>).
- **Stockage** : compte cloud, synchronisé entre appareils quel que
  soit le réglage de synchro de l'historique.
- **UI** : page dédiée, recherche (sauf sur iOS), tri par étoile,
  récence, alphabet ou usage, suppression en lot. Une page « Insights »
  montre les remplacements faits et le mot le plus corrigé.
- **Langues** : une langue par dictée, pas de code-switching ; les
  remplacements ne dépendent pas de la langue
  (<https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages>).

Un outil tiers lit l'historique local de Wispr pour retrouver les mots
mal entendus et ajouter des corrections en lot
(<https://github.com/yahyabedirhan/skills/issues/33>). Signe que
l'auto-apprentissage ne suffit pas pour les noms de produits et de
commandes.

### Apple, pour comparer

Le Contrôle vocal du Mac accepte 1 000 termes par langue, avec
prononciation enregistrée et import/export texte, mais pas d'API
(<https://support.apple.com/guide/mac-help/mchl3eb7b79a/mac>). La
dictée iOS n'a pas de dictionnaire utilisateur.

## Où stocker le lexique

| Option | Pour | Contre |
| --- | --- | --- |
| iPhone seul (aujourd'hui, UserDefaults) | dictée hors ligne, avant même la connexion SSH ; pas de latence ; rien à installer sur le Mac | pas de sauvegarde hors iPhone ; pas éditable ailleurs |
| Mac source de vérité (SQLite ou fichier), lu par SSH à chaque dictée | éditable au clavier, par Claude, versionnable, partageable avec d'autres outils du Mac | la dictée dépend du Mac joignable (LAN/Tailscale) ; latence d'une commande SSH au démarrage ; nouvelle commande `dispatch.sh`, donc nouveau contrat à tester des deux côtés ; `sqlite3` en shell pour quelques centaines de lignes |
| iPhone pour dicter, miroir JSON sur le Mac synchronisé à chaque connexion SSH | dictée locale ; survit à une réinstallation ; liste éditable au clavier ou par Claude | deux commandes `dispatch.sh` de plus ; fusion à écrire (dates et pierres tombales) |
| iCloud (KVS ou CloudKit) | sauvegarde et synchro Apple sans le Mac | aucun second appareil Apple ne s'en sert aujourd'hui ; CloudKit demande une configuration de conteneur |
| iPhone source de vérité, plus export/import | sauvegarde et édition au besoin, sans dépendance à la dictée | geste manuel |

Le volume se compte en centaines d'entrées : une base est
surdimensionnée, et elle ne règle aucun des quatre problèmes ci-dessus.
Le vrai besoin est ailleurs : ne rien perdre à une désinstallation. Le
lexique est dans UserDefaults, effacé avec l'app, comme `PairedMac` :
une réinstallation impose déjà de réappairer le Mac.

Reco : un miroir sur le Mac, pas une source de vérité.

- **Local d'abord** : l'iPhone garde sa copie, et la dictée ne lit
  jamais le Mac. Elle marche hors ligne et sans latence.
- **Un fichier, pas une base** : `~/.config/heraldr/lexique.json` sur le
  Mac, à côté de la clé APNs. C'est du JSON versionné, au format du
  fichier local de l'app, qui quitte UserDefaults pour Application
  Support. VoiceInk fait pareil avec son format `voiceink.dictionary`
  ([DictionaryArchive.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/Workflows/DictionaryArchive.swift#L3-L43)).
- **Deux commandes `dispatch.sh`** : `lexicon-get` (le fichier sur la
  sortie standard, vide s'il n'existe pas) et `lexicon-put` (lu sur
  l'entrée standard, écrit par fichier temporaire puis `mv`). Ni
  daemon, ni port. Ce sont deux sous-commandes de plus au contrat
  testé dans `mac/test/dispatch_test.sh`.
- **Quand synchroniser** : à chaque connexion SSH que l'app ouvre déjà
  (statut, envoi), en tâche de fond. Si le lexique local a changé
  depuis la dernière synchro, l'app lit, fusionne et réécrit. Juste
  après un appairage, la première synchro ramène tout : c'est le cas de
  la réinstallation.
- **Fusion par entrée** : chaque entrée porte `updatedAt` ; une
  suppression laisse une pierre tombale, dont l'étape d'apprentissage a
  besoin de toute façon pour ne pas réapprendre ce qu'on a supprimé.
  La plus récente gagne. On peut alors éditer le fichier sur le Mac, à
  la main ou par Claude (ajouter vingt termes métier d'un coup), et
  l'iPhone le reprend à la connexion suivante.

L'alternative iCloud (`NSUbiquitousKeyValueStore`, 1 Mo) survit aussi à
une réinstallation et ne demande aucun code côté Mac. Il faut en
revanche ajouter l'entitlement iCloud, absent aujourd'hui, et on ne peut
pas éditer la liste au clavier du Mac. Le miroir sur le Mac l'emporte
parce qu'il sert aussi à alimenter les termes métier.

## Termes métier

Exemple réel : « Acme » transcrit « ack me ». Il s'agit d'un
terme, une orthographe voulue, auquel s'attachent des variantes
entendues. Les produits mûrs le modélisent ainsi : une cible et
plusieurs déclencheurs (`triggers[]` chez FluidVoice, variantes séparées
par des virgules chez VoiceInk). Superwhisper et Aqua conseillent
d'ajouter chaque variante mal entendue. Proposition de modèle : une
entrée = un voulu (« Acme ») + ses entendus connus
(« ack me », « ak me ») + son origine (saisi, appris, importé,
workspace). Les corrections actuelles deviennent des entendus attachés
à leur voulu.

Trois leviers, du plus sûr au plus incertain :

1. **Remplacement d'un entendu connu par le code** : « ack me »
   fait trois mots et n'apparaît jamais par hasard dans une demande, ce
   qui en fait un remplacement sûr (étape 2). Il ne couvre que les
   variantes déjà vues.
2. **Biais de la reconnaissance** : le terme dans `contextualStrings`,
   et si `fr_FR` le permet, un modèle de langue personnalisé avec sa
   prononciation en X-SAMPA. Seul `DictationTranscriber` en profite :
   c'est l'objet du spike (étape 1). C'est le seul levier qui évite
   l'erreur au lieu de la réparer.
3. **Rapprochement phonétique d'une variante jamais vue** : comparer
   les groupes de 1 à 3 mots de la transcription, accolés
   (« ack me »), aux termes. Handy procède ainsi
   ([text.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/audio_toolkit/text.rs#L79-L235)).
   La distance d'édition brute ne suffit pas sur l'exemple :
   « ack me » contre « acme » donne 3 sur 10, au-dessus du
   seuil de 0,18 de Handy, et leurs Soundex diffèrent (A251, A250).
   Il faut une clé phonétique française (« ak mee » contre
   « ack mee » : une consonne d'écart), réglée sur le corpus. Un
   rapprochement ne doit pas remplacer directement : il propose le
   terme au modèle comme seul candidat, ou dans l'aperçu.

D'où viennent les termes :

- saisie et import en lot : le fichier sur le Mac (section précédente)
  s'y prête ;
- ce que l'app connaît déjà sans rien demander : libellés des
  workspaces et des tabs herdr, noms d'agents. Wispr lit de même les
  noms de fichiers et de variables dans les éditeurs
  (<https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness>) ;
- l'apprentissage, quand le voulu d'une correction ressemble à un nom
  propre ou à un terme technique.

Les termes saisis ou importés comptent en priorité dans les 100 places
du biais de reconnaissance. Les autres prennent ce qui reste, par
usage.

## UI : une page dédiée

Ce qui revient chez les autres :

| Fonction | Exemples |
| --- | --- |
| page à part, recherche | Wispr, OpenWhispr, FluidVoice ; l'absence de recherche est un ticket ouvert chez VoiceInk ([#654](https://github.com/Beingpax/VoiceInk/issues/654)) |
| tri par récence ou par usage | Wispr ; l'usage est demandé chez OpenWhispr ([#399](https://github.com/OpenWhispr/openwhispr/issues/399)) |
| marque de priorité | étoile chez Wispr |
| origine visible (appris ou saisi) | colonne `source` chez OpenWhispr ; demandée chez VoiceInk ([#965](https://github.com/Beingpax/VoiceInk/issues/965)) |
| propositions à valider | FluidVoice, mode « Manually » de VoiceInk, assistants de Dragon |
| ajout depuis une transcription | Wispr (historique), « Add to vocabulary » du Contrôle vocal |
| statistiques | « Insights » de Wispr |

Pour Heraldr, une page « Lexique », ouverte depuis l'accueil ou depuis
l'aperçu d'une dictée plutôt que du fond des Réglages, avec deux
sections :

- **À valider** : suggestions apprises, chacune avec la phrase d'où
  elle vient ; « Retenir » ou « Ignorer » ; un refus n'est plus jamais
  reproposé ;
- **Termes** : l'orthographe voulue et ses variantes entendues, nombre
  d'applications, origine ; une étoile envoie le terme en priorité au
  biais de reconnaissance.

Plus une recherche, et dans l'aperçu, le geste « appuyer sur un mot →
Corriger » qui crée une correction explicite. C'est un apprentissage
sans bruit, puisque l'intention est claire.

La confirmation « Retenir X → Y ? » avait été écartée (decisions.md),
mais c'était une question posée à l'envoi, qui interrompait. Une liste
à valider plus tard, qui ne s'affiche qu'au bout de deux occurrences,
n'a pas ce coût.

## Plan d'itération

Chaque étape est livrable seule et mesurable. Les étapes 1, 2 et 4
visent directement « pas précis », la 3 protège contre la perte, la 5
évite que ça se redégrade, la 6 est le confort.

**0. Mesurer avant de changer**

- Garder pour chaque dictée envoyée : la transcription brute, le texte
  nettoyé et le texte envoyé. L'historique et « Voir l'original » en
  ont déjà une partie.
- Ajouter un export du tout.
- Constituer 20 à 30 dictées réelles enregistrées, avec les termes
  qui posent problème (herdr, worktree, Claude, noms de branches).
- Critère : taux de termes du lexique bien écrits avant toute retouche
  à la main.
- Sans ce corpus, impossible de dire si une étape aide.

**1. Spike transcripteur** (résultat dans `docs/risks.md`)

- Vérifier que `setContext` est sans effet sur `SpeechTranscriber`.
  Retirer le `try?` muet, ou au moins tracer l'erreur.
- Sur le corpus, comparer :
  - `SpeechTranscriber` sans biais ;
  - `DictationTranscriber` avec ≤ 100 termes ;
  - `DictationTranscriber` avec modèle de langue personnalisé
    (prononciations X-SAMPA pour herdr, worktree ; gabarits) si
    `fr_FR` le permet.
- Tester aussi les options `alternativeTranscriptions` et
  `transcriptionConfidence` de `SpeechTranscriber`
  (<https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption>),
  qui pourraient cibler la correction sur les passages incertains.
- Décision à prendre : quel transcripteur. Si `SpeechTranscriber`
  l'emporte, cesser d'y passer un vocabulaire qu'il ignore.

**2. Termes et variantes, remplacés par le code**

- Nouveau modèle : un voulu, ses entendus, son origine, `updatedAt`,
  des pierres tombales. Stocké en JSON versionné dans Application
  Support. Les corrections actuelles sont migrées en entendus.
- Remplacer les entendus connus par du code, après le nettoyage : mots
  entiers, insensible à la casse et aux accents, plus long d'abord,
  casse du voulu gardée.
- Pour limiter les faux positifs qui avaient fait écarter cette option,
  n'appliquer automatiquement qu'un entendu sûr :
  - de deux mots ou plus (« ack me ») ;
  - ou d'un mot qui n'est pas un mot français courant ;
  - ou validé explicitement.
- Pour les autres, ne donner au modèle que les 0 à 3 paires dont
  l'entendu apparaît dans la transcription, formulées sur la dictée
  (« ici, X veut probablement dire Y »), au lieu des 20 plus récentes.
  Variante plus stricte : `@Generable` qui renvoie la liste des
  substitutions retenues parmi ces candidates, appliquées et vérifiées
  par le code.
- Ce changement révise la décision « remplacement textuel déterministe
  écarté (faux positifs) » : à consigner dans `docs/decisions.md` et la
  spec §5.1 si retenu.

**3. Miroir sur le Mac**

- `dispatch.sh lexicon-get` / `lexicon-put`, fichier
  `~/.config/heraldr/lexique.json`, tests de contrat des deux côtés.
- Synchro en tâche de fond à chaque connexion SSH, fusion par entrée.
  Juste après un appairage, la première synchro restaure tout.
- Peut passer avant l'étape 2 si la perte du lexique presse : le JSON
  versionné absorbe le changement de modèle.

**4. Termes métier**

- Termes tirés des workspaces, des tabs et des agents herdr ; import en
  lot par le fichier du Mac.
- Rapprochement phonétique des variantes jamais vues (clé phonétique
  française plus distance d'édition, seuil réglé sur le corpus),
  proposé au modèle comme seul candidat, jamais remplacé d'office.

**5. Apprentissage en suggestions**

- Une substitution détectée à l'envoi devient une candidate, pas une
  entrée.
- Filtres :
  - garder le seuil de réécriture ;
  - ajouter une similarité phonétique ou d'écriture entre entendu et
    voulu (distance d'édition normalisée, à régler sur le corpus de
    l'étape 0), qui écarte « regarde → vérifie » ;
  - exclure les nombres et les chemins.
- Une candidate vue deux fois passe dans « À valider ». Une correction
  explicite (geste « Corriger » dans l'aperçu ou saisie) entre
  directement.
- Les pierres tombales empêchent de réapprendre ce qui a été supprimé
  ou refusé.
- Classer par usage (`count`, dernière application) plutôt que par
  récence. Relever le plafond, puisque seul le canal de reconnaissance
  est limité (≤ 100).

**6. Page « Lexique »**

- Sections À valider / Termes, chaque terme avec ses variantes,
  recherche, compteurs, étoile.
- Accès depuis l'accueil et l'aperçu, geste « Corriger » sur un mot.

**7. Plus tard, si le besoin apparaît**

- Synchro iCloud si un second appareil Apple dicte.

## Points ouverts

- Comportement réel de `setContext` sur `SpeechTranscriber` dans iOS 26
  (lève ou ignore).
- Support de `fr_FR` par les modèles de langue personnalisés et
  phonèmes acceptés.
- Précision comparée des deux transcripteurs en français mêlé
  d'anglais : aucune mesure publiée.
- Fiabilité de `transcriptionConfidence` sur les termes techniques.
- Mécanisme exact de biais chez Wispr Flow, non documenté.
- Retours d'utilisateurs Reddit non consultés : site inaccessible
  pendant la veille.
