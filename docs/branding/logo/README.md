# Logo : propositions

Symboles seuls, sans nom (le nom n'est pas encore choisi). SVG
1024x1024 à fond plein et sans coins arrondis : iOS applique lui-même
le masque squircle. Le motif reste dans le cercle central d'environ
700 px pour survivre au masque et rester lisible à 60 px.

Aperçu : ouvrir `index.html` (180 et 60 px sur fond clair et sombre,
1024 px dépliable).

Onde et prisme ont été écartés après le premier tour. Le deuxième tour
(plus bas) décline voix et voies et retravaille l'éventail.

## 1. Éventail (recommandé)

`1-eventail.svg`, variantes `1-eventail-dark.svg` et
`1-eventail-tinted.svg`.

Un disque de verre (le gros bouton voix) d'où partent trois branches
qui s'écartent vers trois points : une intention, plusieurs worktrees.
Les trois couleurs reprennent les états des agents de l'écran
principal (bleu working, vert done, orange blocked), ce qui lie l'icône
à l'UI. Le disque translucide à liseré clair est la référence Liquid
Glass la plus directe des cinq.

Pourquoi en premier : c'est le seul qui dit à la fois le geste (le
bouton) et l'effet (un vers plusieurs), il reste lisible à 60 px et
ne ressemble à aucune icône système connue. Risque : proche d'un
pictogramme de graphe ou de partage, à surveiller si le nom ne vient
pas l'ancrer.

## 5. Voix et voies

`5-voies.svg`, variantes `5-voies-dark.svg` et `5-voies-tinted.svg`.

Une onde de voix qui se divise en trois voies parallèles. Le jeu de
mots voix/voies marche en français uniquement. Monochrome, donc très
propre en mode teinté. Moins Liquid Glass que l'éventail et l'onde
devient fine à 60 px (corrigé au deuxième tour).

## 4. Troupeau

`4-troupeau.svg`.

Un meneur cerclé de verre et cinq points en formation de vol pointée
vers la droite : le coup de sifflet qui envoie le troupeau, clin d'oeil
direct à herdr. Le plus chaleureux, mais la lecture « envoi » dépend de
la formation en V, moins nette en petit.

## Variantes iOS 26

Pour les deux premiers et pour les deux retenus de chaque famille du
deuxième tour : `-dark` garde les couleurs du motif sur un
fond quasi noir, `-tinted` est un motif en niveaux de gris sur noir que
le système colorise avec la teinte choisie. Dans Icon Composer, il
faudra séparer fond et calques du motif pour que le rendu Liquid Glass
natif (reflets, profondeur) s'applique au lieu des dégradés dessinés
ici.

## Deuxième tour

### Voix et voies

Trait porté de 60 à 72-80 px pour tenir à 60 et 40 px, et un court
tronc droit entre l'onde et la séparation pour que la voix et le
dispatch se lisent comme deux temps distincts. Les voies se séparent en
S doux (courbes de Bézier à tangentes horizontales).

- `voies-v2-a-epais.svg` (recommandé, avec `-dark` et `-tinted`) :
  l'original épaissi, onde sinusoïdale simple, blanc sur vert d'eau.
  Le plus lisible en petit et le plus propre en teinté.
- `voies-v2-b-statuts.svg` (avec `-dark` et `-tinted`) : onde plus
  parlée (amplitudes inégales), chaque voie passe du blanc à sa couleur
  d'état ; longueurs différentes, la verte (done) va jusqu'au bout,
  l'orange (blocked) s'arrête tôt. Fond nuit.
- `voies-v2-c-clair.svg` : fond clair, onde encre, voies aux couleurs
  d'état qui prennent le relais au point de séparation.
- `voies-v2-d-quatre.svg` : quatre voies plus fines aux longueurs
  décalées, sur dégradé orange-framboise. Plus chargé à 40 px.
- `voies-v2-e-verre.svg` : motif en tube de verre (liseré clair,
  cœur bleuté, ombre portée) sur bleu. Le plus Liquid Glass de la
  famille, mais le rendu dessiné fait un peu skeuomorphe.

Écarté en cours de route : deux voies (se lit « wc »), onde à épaisseur
croissante et trois ondes qui se désentrelacent (brouillon à la
jonction). Limite commune à toute la famille : la partie droite peut se
lire comme un E ou un €.

### Éventail

Le disque devient un vrai bouton (micro, reflet en haut, ombre portée)
et les branches perdent leur aspect de graphe : plus de points ronds
au bout ni de traits d'épaisseur constante.

- `eventail-v2-b-lames.svg` (recommandé, avec `-dark` et `-tinted`) :
  trois lames de verre colorées déployées en éventail autour du bouton
  blanc, qui se superposent par transparence. Littéralement un éventail,
  le plus lisible à 40 px, le plus proche du rendu Liquid Glass.
- `eventail-v2-a-comete.svg` (avec `-dark` et `-tinted`) : bouton bleu
  au micro blanc, trois traînées effilées qui partent transparentes et
  finissent pleines dans leur couleur d'état, comme lancées par le
  bouton.
- `eventail-v2-d-givre.svg` : la comète en monochrome, bouton de verre
  dépoli et traînées blanches sur bleu vif. Le plus sobre et le plus
  « Apple ».
- `eventail-v2-e-givre-lames.svg` : les lames en verre dépoli blanc sur
  violet. Élégant mais moins contrasté en petit.
- `eventail-v2-c-aube.svg` : éventail vertical, bouton en bas et lames
  vers le haut, sur fond clair. Plus ludique, frôle la main ou le
  bouquet.
