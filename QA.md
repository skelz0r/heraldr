# QA manuelle

Heraldr s'installe directement sur l'iPhone (`bin/run-ios-device`), sans
TestFlight. Avant de garder un build qui touche un parcours ci-dessous,
dérouler les cases concernées sur le vrai iPhone, avec le vrai Mac.

## Principes

- Tester ce que les tests automatiques ne voient pas : vrai SSH (LAN et
  Tailscale), vrai herdr, vrai Claude, dictée et Apple Intelligence,
  caméra, push APNs, lien universel vers l'app Claude, rendu au doigt.
- Le comportement attendu est dans `docs/spec.md`. En cas de doute, la
  spec fait foi.
- Un bug trouvé se note avec l'écran, le parcours, le résultat observé
  et une capture dans `~/share/screenshots/`. Une régression sur un
  parcours ci-dessous se corrige avant de continuer.

## Smoke test

- [ ] Installer par-dessus la version précédente : l'app s'ouvre
  appairée, Home en cible, les workspaces dans l'ordre herdr.
- [ ] Écrire une demande vers un projet dont le `-main` est prêt :
  notice « Envoyé », sur le Mac `/clear` puis la consigne, l'état de
  la cible passe à « Travaille sur ta demande ».
- [ ] Envoyer vers un projet sans `-main` : l'agent apparaît dans le
  tab 1 et reçoit la demande ; sa session Remote Control porte
  `<label>—main` dans Claude mobile.
- [ ] Envoyer vers un agent qui travaille : notice « En file », badge
  « en attente », la demande part quand il a fini.
- [ ] Dicter plus longtemps que le verrouillage automatique : l'écran
  reste allumé ; après l'arrêt, il se verrouille au délai habituel.
- [ ] Dicter une demande avec des hésitations : « Dictée nettoyée »,
  « Voir l'original » montre la transcription brute.
- [ ] Dicter « on push la branche », corriger en « git push » dans
  l'aperçu et envoyer, puis redicter la même phrase : l'aperçu propose
  « git push », même Apple Intelligence désactivé.
- [ ] Réglages > Lexique : le terme « git push » et sa variante
  « on push » apparaissent ; le pied dit « Sauvegardé sur le Mac » et
  `~/.config/heraldr/lexique.json` les contient sur le Mac.
- [ ] Désinstaller l'app, la réinstaller et l'appairer : notice
  « Lexique restauré depuis le Mac », la liste est revenue.
- [ ] Après une dictée, corriger un mot au clavier, puis « Dicter la
  suite » : la nouvelle salve s'ajoute à la ligne, la correction reste ;
  « Voir l'original » montre les deux salves. Relancer « Dicter la
  suite » puis « Annuler » : retour à l'aperçu, texte intact.
- [ ] Coller une demande depuis le presse-papier, puis avec un
  presse-papier vide : notice « Presse-papier vide ».
- [ ] Joindre deux captures depuis l'aperçu, en retirer une, envoyer
  à un projet : le `-main` reçoit la demande avec le chemin de la
  capture et la décrit. Faire une capture, « Copier et supprimer »,
  puis Coller : l'aperçu s'ouvre avec la vignette. Renvoyer depuis
  l'historique : « 1 capture jointe », le même chemin repart.
- [ ] Envoyer à Home une demande qui vise un projet ouvert : Home la
  relaie, l'envoi s'affiche sur la ligne du projet et c'est son `-main`
  qui lance `/start`.
- [ ] Appui long sur un workspace avec une feature en cours : le menu
  liste ses tabs qui ont un Claude ; en choisir un, son nom s'affiche
  sous celui du workspace dans la cible. Envoyer un retour sans cocher « Envoyer /clear
  avant » : le Claude du tab reçoit l'avertissement de dictée puis le
  texte, sans consigne, contexte gardé.
  Un tap sur la tuile revient sur `main`.
- [ ] Faire poser une question AskUserQuestion à un `-main` : la notif
  arrive avec label, agent et question ; le tap ouvre la session dans
  l'app Claude, app en arrière-plan comme app tuée.
- [ ] Envoyer à un projet une simple question (« comment marche X
  dans Y ») : pas de /start, la notif « Réponse » porte le résumé ; le
  tap ouvre la feuille avec la question et la réponse complète, app en
  arrière-plan comme app tuée. L'historique la range dans « Questions ».
  Même question envoyée à Home : Home répond lui-même, sans relais.
- [ ] Couper le Wi-Fi avec Tailscale actif : l'app joint le Mac par
  Tailscale. Couper aussi Tailscale : la pastille du Mac passe en
  orange, la liste reste ; « Rafraîchir » une fois le réseau revenu la
  remet en vert.
- [ ] Lancer l'app réseau coupé : « Mac injoignable », puis
  « Réessayer » une fois le réseau revenu.
- [ ] Envoyer une demande Mac injoignable : l'aperçu montre l'erreur ;
  fermer l'aperçu, l'historique garde le texte en « Échec ». Une fois
  le Mac revenu, « Renvoyer » : notice d'envoi, nouvelle entrée qui
  passe « En file » puis « Envoyé ». « Copier » colle bien le texte.

## Quand l'appairage change

- [ ] « Oublier ce Mac », puis appairer avec le QR de `heeler.pair` :
  retour sur l'écran principal, Home en cible.
- [ ] Coller un code expiré : « Le code a expiré : relance heeler.pair
  sur le Mac ».
