# Risques et points à vérifier

À lever par un spike avant d'écrire l'app.

1. `/clear` et Remote Control : le nom `<label>—main` et la connexion
   Remote Control survivent-ils à un `/clear` ? Sinon, relancer
   `/remote-control <nom>` après chaque `/clear` dans le script de
   dispatch.
2. Nom Remote Control : le tiret cadratin et `~` passent-ils dans
   `--remote-control` et l'affichage Claude mobile ?
3. `remoteControlAtStartup: true` dans les settings : conflit ou doublon
   avec `--remote-control <nom>` ?
4. `herdr agent prompt` d'un texte multi-lignes : vérifier que le
   bracketed paste conserve les retours à la ligne dans Claude Code.
5. Format `HERDR-PAIR:1` : couplage à une version du plugin Heeler.
   Épingler la version testée et lancer les vecteurs de test en CI
   locale.
6. HeelerSSH : API publique stable ? Taille du binaire OpenSSL. Plan B :
   Citadel si streamlocal y est supporté.
7. Process détaché via `nohup` en exec SSH : vérifier qu'il survit à la
   fermeture du canal sur macOS (sinon `setsid` ou `launchctl submit`).
8. Foundation Models : qualité du nettoyage en français, limite de
   contexte pour une longue dictée.
9. Chemin de `herdr.sock` avec plusieurs sessions herdr nommées.
