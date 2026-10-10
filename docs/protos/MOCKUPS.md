# Maquettes — directions UI du compagnon herdr

Quatre directions pour l'écran principal de l'app iOS. Elles ne diffèrent
que sur **la disposition de l'accueil** : liste des workspaces, cible des
envois, boutons Écrire · Dicter · Coller. Appairage, dictée, nettoyage,
aperçu, file d'attente et erreurs sont identiques partout.

Point d'entrée : `index.html` (ouvrir directement depuis le disque ou via
`python3 -m http.server`).

## Règle d'itération

**Tout est engendré par `build.py`. On itère là, jamais dans les fichiers
HTML**, écrasés à chaque exécution :

```bash
cd docs/protos && python3 build.py
```

Le script signale les liens cassés, les repères sans annotation et les
annotations sans repère.

## Les directions

| Direction | Accueil | Voix | Statut |
|---|---|---|---|
| `direction-a` | liste de rangées en verre, dock flottant | 92 pt dans le dock | repli bon marché |
| `direction-b` | carrousel de pastilles, cible en grand | orbe de 224 pt au centre | |
| `direction-c` | pile de cartes colorées façon Cartes | tuile haute | |
| `direction-d` | lecture en haut, grille deux colonnes en bas | 128 pt en saillie | recommandée |

Chaque direction : 7 écrans en ligne droite (appairage, accueil, cible
choisie, dictée, nettoyage, aperçu, envoi mis en file) et 5 écrans hors
parcours (Écrire, Coller, changer de cible, Mac injoignable, transcription
brute).

## Conventions de lecture

- Le bandeau rappelle la direction et la position, avec Précédent et
  Suivant, et un sélecteur Clair · Sombre · Les deux.
- Les éléments touchables du téléphone mènent à l'écran suivant.
- Commentaires en marge, numérotés : bleu un constat, vert un point fort,
  orange une faiblesse.
- Le Mac, le compte et les adresses sont fictifs ; les noms des workspaces
  sont réels.

## Ce que les maquettes ne montrent pas

- **Le vrai Liquid Glass.** Réfraction, lumière liée à l'inclinaison et
  morphose ne sont qu'approchées en CSS (flou, translucidité, reflets).
- **Les transitions.** Seuls le dot bleu, l'onde et le nettoyage sont
  animés.
- **Le pull-to-refresh.** Identique partout, sans effet sur la décision.
- **Le hors MVP.** Réponse aux questions, notifications, détail par agent,
  historique.
