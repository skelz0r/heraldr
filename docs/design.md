# Design

Référence du rendu de l'app Heraldr. Les valeurs vivent dans
`ios/Heraldr/UI/Theme.swift` et `AccentColor` de l'asset catalog.

## Palette

| Token | Clair | Sombre | Usage |
| --- | --- | --- | --- |
| `accent` | `#0E7A66` | `#5FD3BA` | orbe voix, tuile cible, Envoyer, liens, coches |
| `onAccent` | `#FFFFFF` | `#04241D` | texte et icônes posés sur l'accent ou une pastille d'état |
| `wallBase` | `#EEF3F1` | `#050607` | fond de tous les écrans |
| `wallBlobOne` | `#A8EBD9` | `#0E3B32` | tache floue, en haut à gauche |
| `wallBlobTwo` | `#C9D6F2` | `#151A2C` | tache floue, à droite |
| `wallBlobThree` | `#9FE0F0` | `#0B2A33` | tache floue, en bas |
| `recording` | `#D70015` | `#FF453A` | bouton Arrêter de la dictée |

L'accent vient du logo (`#9FF0DD`, `#5FD3BA`, `#2FA88F`) : `#5FD3BA` tel
quel en sombre, foncé à `#0E7A66` en clair pour porter du blanc. Le texte
reste celui du système (`.primary`, `.secondary`).

Contrastes (WCAG 2.1) :

- `onAccent` sur `accent` : 5,3:1 en clair, 9,0:1 en sombre (AA texte)
- `accent` en texte sur `wallBase` : 4,7:1 en clair, 11:1 en sombre
- les tuiles et l'orbe sont en Liquid Glass teinté : la translucidité
  rapproche un peu la couleur du fond, d'où des valeurs choisies avec
  de la marge

## Couleurs d'état

| État | Clair | Sombre | Sur `wallBase` (clair / sombre) |
| --- | --- | --- | --- |
| idle | `#6B7075` | `#8E9399` | 4,5 / 6,5 |
| working | `#005FCC` | `#4DA3FF` | 5,3 / 7,6 |
| blocked | `#A84F00` | `#FF9F0A` | 5,0 / 9,8 |
| done | `#3F8A12` | `#8BD450` | 3,9 / 11,1 |

working, blocked et idle servent aussi de texte (badge « en attente »,
erreurs) : en clair, ils tiennent 4,5:1. done n'est jamais du texte
(dot et pastille d'icône seulement) : 3:1 suffit pour un élément
graphique.

Conflit done / accent : le vert système (teinte 135°) était trop proche
du vert d'eau (167°). done passe à un vert jaune (97°), soit plus de 70°
d'écart, et un dot posé sur la tuile cible est toujours cerclé de
`onAccent`. La couleur ne porte jamais seule l'information : le libellé
d'état est écrit sous la cible.

working pulse (anneau qui s'élargit), blocked a un halo fixe.

## Typographie

SF Pro, sans police embarquée.

| Élément | Style |
| --- | --- |
| Nom de la cible | SF Pro Rounded heavy 44 pt, 88 pt pour `~`, tracking -1 |
| Libellé « CIBLE » | caption heavy, capitales, tracking 1,2 |
| État de la cible | callout semibold, puis footnote secondaire |
| Tuile workspace | 15 pt semibold, deux lignes au plus |
| Dictée en direct | SF Pro Rounded semibold 26 pt, mots provisoires en secondaire |
| Aperçu | 19 pt medium |

## Tailles

- orbe voix : 128 pt, en saillie au-dessus de la barre, cerclé de 12 pt
  de `wallBase` ; d'abord fixé à 180 pt, réduit car il masquait la
  grille
- barre Écrire / Coller : capsule de 92 pt de haut, 12 pt des bords
- grille : deux colonnes, 8 pt d'écart, 16 pt de marge ; le premier
  workspace (`~`) occupe toute la largeur au-dessus
- tuile : 58 pt de haut minimum, coins de 20 pt
- dictée : Arrêter 112 pt, Annuler 64 pt
- aperçu : Envoyer pleine largeur, 64 pt de haut ; Fermer 44 pt
- toute cible tactile fait au moins 44 pt

## Liquid Glass

`glassEffect` d'iOS 26, sans matériau imité.

- verre simple `.regular` : barre Écrire / Coller, tuiles, pilule du
  Mac, bandeau cible et texte de l'aperçu, notices
- verre teinté accent : orbe voix, tuile cible, Envoyer
- verre teinté `recording` : bouton Arrêter
- `.interactive()` sur tout ce qui se touche
- pas de verre : le fond (`Wallpaper`, couleurs et flou), le texte
  courant, les listes système (choix de la cible)

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
