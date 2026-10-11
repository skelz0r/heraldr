# Design

Référence du rendu de l'app Heraldr. Les valeurs vivent dans
`ios/Heraldr/UI/Theme.swift` et `AccentColor` de l'asset catalog.

## Palette

« Graphite et gueules » : tout est verre neutre, presque monochrome, et
une seule couleur vive, le vermillon des blasons (« gueules »),
réservée à la voix. La sélection ne prend pas de couleur, elle prend
de la lumière.

| Token | Clair | Sombre | Usage |
| --- | --- | --- | --- |
| `accent` | `#C2321A` | `#FF5A3C` | Envoyer, Arrêter, onde de dictée, flèche de la cible, liens, coches |
| `onAccent` | `#FFFFFF` | `#FFFFFF` | texte et icônes posés sur l'accent |
| `voiceInk` | `#C2321A` | `#FF7A5C` | micro de la goutte |
| `voiceGlow` | `#FF5A3C` | `#FF5A3C` | lueur au fond de la goutte, halo du micro |
| `selectedGlass` | blanc 92 % | blanc 20 % | teinte du verre de la tuile cible |
| `restingGlass` | `#8A8D96` à 12 % | aucune | teinte des autres tuiles, pour que la cible ressorte en clair |
| `selectedGlow` | noir 10 % | blanc 10 % | ombre de la tuile cible |
| `onStatus` | `#FFFFFF` | `#121214` | icône posée sur une pastille d'état (notices) |
| `macOnline` | `#1F8A4C` | `#6EDB8F` | dot du Mac en ligne, seul vert de l'app |
| `wallBase` | `#F1F1F3` | `#0B0B0D` | fond de tous les écrans |
| `wallBlobOne` | `#D8DAE0` | `#26282E` | tache floue, en haut à gauche |
| `wallBlobTwo` | `#E4E7EE` | `#1A1D24` | tache floue, à droite |
| `wallBlobThree` | `#F4D3CB` | `#3A1712` | tache floue, en bas : lueur rouge discrète sous la goutte |

Le texte reste celui du système (`.primary`, `.secondary`).

Contrastes (WCAG 2.1) :

- `accent` en texte sur `wallBase` : 4,9:1 en clair, 6,3:1 en sombre
- `onAccent` sur `accent` : 5,6:1 en clair, 3,1:1 en sombre ; en
  sombre, le blanc n'est posé que sur du texte large (Envoyer, title3
  gras) ou une icône, où 3:1 suffit
- micro `voiceInk` sur `wallBase` : 4,9:1 en clair, 7,7:1 en sombre
- `onStatus` sur les pastilles d'état : 5,2:1 au moins

## Couleurs d'état

| État | Clair | Sombre | Sur `wallBase` (clair / sombre) | Dot |
| --- | --- | --- | --- | --- |
| idle, inconnu | `#6A6C73` | `#D7D8DD` | 4,6 / 13,8 | anneau |
| done | `#6A6C73` | `#D7D8DD` | 4,6 / 13,8 | pastille pleine |
| working | `#0A63C9` | `#64C8FF` | 5,1 / 10,5 | pastille, anneau qui pulse |
| blocked | `#8F5400` | `#FFC23D` | 5,4 / 12,2 | pastille, halo fixe |

Le vert sort des états : idle et done mènent tous deux à « Prêt », ils
partagent le gris « prêt » et ne diffèrent que par la forme (anneau ou
pastille). Seuls working et blocked prennent une couleur, et rien ne
leur fait concurrence. La couleur ne porte jamais seule l'information :
le libellé d'état est écrit sous la cible.

Notices et historique : envoyé en gris « prêt », en file en bleu
working, échec en ambre blocked.

## Typographie

SF Pro, sans police embarquée.

| Élément | Style |
| --- | --- |
| Nom de la cible | SF Pro Rounded heavy 44 pt pour tous, tracking -1 |
| Libellé « CIBLE » | caption heavy, capitales, tracking 1,2 |
| État de la cible | callout semibold, puis footnote secondaire |
| Tuile workspace | 15 pt semibold, deux lignes au plus |
| Dictée en direct | SF Pro Rounded semibold 26 pt, mots provisoires en secondaire |
| Aperçu | 19 pt medium |

## Tailles

- goutte voix : 92 pt, au centre de la barre du bas, entre deux ronds
  de verre de 54 pt (Écrire, Coller), 16 pt d'écart ; icônes seules,
  libellés pour VoiceOver. Avant : orbe de 104 pt en saillie sur une
  capsule de 92 pt, détaché par un anneau de `wallBase`
- micro de la goutte : 30 pt medium ; lueur radiale `voiceGlow` de 55 %
  à 0, centrée sous le bas de la goutte (115 % de sa hauteur), rayon
  72 pt
- grille : deux colonnes, 8 pt d'écart, 16 pt de marge ; le premier
  workspace (Home) occupe toute la largeur au-dessus
- cible : 38 % de la hauteur de l'écran, en `safeAreaBar` du haut de
  la grille
- bords de la grille au défilement : effet de bord `.soft` d'iOS 26 en
  haut et en bas ; en haut, les tuiles s'effacent aussi en fondu sur
  les 56 derniers points de la cible, pour ne jamais passer derrière
  son texte ; en bas, elles passent floutées sous la goutte et les
  ronds
- tuile : 58 pt de haut minimum, coins de 20 pt ; cible en gras, ombre
  `selectedGlow` de rayon 13 pt décalée de 6 pt
- dictée : Arrêter 112 pt, Annuler 64 pt
- aperçu : Envoyer pleine largeur, 64 pt de haut ; Fermer 44 pt
- toute cible tactile fait au moins 44 pt

## Liquid Glass

`glassEffect` d'iOS 26, sans matériau imité.

- verre simple `.regular` : ronds Écrire et Coller, pilule du Mac,
  bandeau cible et texte de l'aperçu, notices
- verre clair `.clear` : goutte voix, sans teinte ni anneau ; la couleur
  n'est que dans la lueur au fond et le micro
- verre teinté `selectedGlass` : tuile cible, plus dense et plus clair
  que les autres, sans couleur (le segment choisi d'un `Picker`)
- verre teinté `restingGlass` : autres tuiles
- verre teinté accent : Envoyer, Arrêter ; Arrêter se distingue de la
  voix par sa forme (carré d'arrêt sur disque plein), pas par sa
  couleur
- `.interactive()` sur tout ce qui se touche
- pas de verre : le fond (`Wallpaper`, couleurs et flou), le texte
  courant, les listes système (choix de la cible)
- Réduire la transparence : le système rend le verre opaque ; la
  lueur et le micro de la goutte, posés dessus, restent colorés et
  la gardent repérable. Contraste augmenté : bordures du système

## Icône

Logo « Voix et voies », source unique dans `docs/branding/logo/` :

- défaut et sombre : `5-voies-dark.svg`
- teintée : `5-voies-tinted.svg`
- trait épaissi de 60 à 80 px au rendu, pour rester lisible à 60 px ;
  le tracé n'est pas modifié

`bin/render-ios-icon` produit les PNG 1024 de l'AppIcon et le logo
affiché dans l'app.

## Pas un look natif standard

- pas de `NavigationStack` ni de `List` sur l'accueil : une composition
  pleine page
- le fond est toujours le dégradé flou, jamais un gris système
- la cible se lit de loin : nom en très grand, état en une phrase
- tout ce qui se touche est dans la moitié basse, utilisable d'une main
- le bouton voix domine, Écrire et Coller restent secondaires
- les écrans annexes (choix de cible, transcription originale) peuvent
  rester des feuilles système
