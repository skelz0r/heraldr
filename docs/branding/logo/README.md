# Logo : propositions

Symboles seuls, sans nom (le nom n'est pas encore choisi). SVG
1024x1024 à fond plein et sans coins arrondis : iOS applique lui-même
le masque squircle. Le motif reste dans le cercle central d'environ
700 px pour survivre au masque et rester lisible à 60 px.

Aperçu : ouvrir `index.html` (180 et 60 px sur fond clair et sombre,
1024 px dépliable).

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
devient fine à 60 px.

## 4. Troupeau

`4-troupeau.svg`.

Un meneur cerclé de verre et cinq points en formation de vol pointée
vers la droite : le coup de sifflet qui envoie le troupeau, clin d'oeil
direct à herdr. Le plus chaleureux, mais la lecture « envoi » dépend de
la formation en V, moins nette en petit.

## 2. Onde

`2-onde.svg`.

Cinq barres de forme d'onde, qui se lisent aussi comme des couloirs
parallèles. Très lisible, mais générique : ressemble à n'importe quelle
app audio ou de dictée, l'idée de dispatch se perd.

## 3. Prisme

`3-prisme.svg`.

Un faisceau blanc entre dans un prisme de verre et ressort en trois
faisceaux colorés : une intention décomposée en travaux parallèles.
Visuellement fort et très « verre », mais trop proche de la pochette
de Dark Side of the Moon pour être retenu tel quel.

## Variantes iOS 26

Pour les deux premiers : `-dark` garde les couleurs du motif sur un
fond quasi noir, `-tinted` est un motif en niveaux de gris sur noir que
le système colorise avec la teinte choisie. Dans Icon Composer, il
faudra séparer fond et calques du motif pour que le rendu Liquid Glass
natif (reflets, profondeur) s'applique au lieu des dégradés dessinés
ici.
