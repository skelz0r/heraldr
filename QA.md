# QA sur l'iPhone

Ce qui reste à la main : ce que ni les tests (unitaires, `dispatch.sh`,
hook, tests UI sur le faux Mac) ni `bin/qa` ne voient, parce qu'il
faut le vrai iPhone et le vrai Mac : SSH réel (LAN, Tailscale), vrai
herdr et vrai Claude, dictée et Apple Intelligence, caméra, push APNs,
lien vers l'app Claude, verrouillage d'écran.

Personne ne déroule cette liste en entier. Après un
`bin/run-ios-device`, l'agent présente à l'utilisateur 3 à 5 cases au
plus, choisies parmi les zones que touche le diff (chemins entre
parenthèses), et jamais une case que les tests couvrent déjà. Un
défaut trouvé se reproduit d'abord en test (faux Mac, `fake-herdr`)
quand c'est possible, puis se corrige.

## Envoi de bout en bout (Dispatch/, mac/dispatch.sh, Mac/)

- [ ] Écrire une demande vers un projet sans `-main` : l'agent naît
  dans le tab 1, sa session porte `<label>—main` dans Claude mobile, il
  reçoit `/clear` puis la consigne.
- [ ] Envoyer à Home une demande qui vise un projet ouvert : Home la
  relaie, c'est le `-main` du projet qui lance `/start`.
- [ ] Joindre deux captures depuis la photothèque et envoyer : le
  `-main` lit les images par leur chemin et les décrit.

## Réseau (Mac/, Pairing/)

- [ ] Wi-Fi coupé, Tailscale actif : l'app joint le Mac par Tailscale.
  Tailscale coupé aussi : pastille orange, liste gardée ; une fois le
  réseau revenu, « Rafraîchir » la remet en vert.
- [ ] « Oublier ce Mac », puis appairer en scannant le QR de
  `heeler.pair` : retour sur l'écran principal, Home en cible.
- [ ] Installer par-dessus la version précédente : l'app s'ouvre
  appairée, l'historique et le lexique sont gardés.

## Dictée (Voice/, UI/ComposeView.swift)

- [ ] Dicter une demande avec des hésitations : « Dictée nettoyée »,
  « Voir l'original » montre la transcription brute.
- [ ] Dicter plus longtemps que le verrouillage automatique : l'écran
  reste allumé, puis se verrouille au délai habituel après l'arrêt.
- [ ] Avec Spotify en lecture, dicter puis arrêter : la musique se
  coupe pendant l'écoute et reprend seule à l'arrêt, sans erreur dans
  Spotify ; idem avec « Annuler » et en verrouillant l'iPhone pendant
  la dictée (au retour, l'aperçu montre ce qui a été dicté).
- [ ] Dicter « on push la branche », corriger en « git push » et
  envoyer, puis redicter : l'aperçu propose « git push » ;
  `tail -1 ~/.config/heraldr/journal-dictees.jsonl` sur le Mac montre
  le remplacement.
- [ ] Désinstaller, réinstaller, appairer : « Lexique restauré depuis
  le Mac ».

## Notifications (Push/, mac/notify-hook.mjs)

- [ ] Faire poser une question AskUserQuestion à un `-main` : la notif
  arrive avec label, agent et question ; le tap ouvre la session dans
  l'app Claude.
- [ ] Envoyer une simple question à un projet : notif « Réponse » avec
  le résumé, le tap ouvre la feuille avec la réponse complète.
