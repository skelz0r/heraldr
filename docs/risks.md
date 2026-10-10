# Risques et points à vérifier

À lever par un spike avant d'écrire l'app. Résultats du spike du
2026-10-10 (herdr 0.9.3, Claude Code 2.1.296, macOS 26.4), sur un
workspace jetable « Spike compagnon » et son agent
`spike-compagnon-main`.

1. `/clear` et Remote Control : le nom `<label>—main` et la connexion
   Remote Control survivent-ils à un `/clear` ? Sinon, relancer
   `/remote-control <nom>` après chaque `/clear` dans le script de
   dispatch.
   - Levé : après `/clear`, la boîte `/remote-control` affiche la même
     URL `claude.ai/code/session_…` qu'avant. La connexion survit, pas
     besoin de relancer `/remote-control`.
   - Nouveau constat : `herdr agent prompt <agent> "/clear" --wait`
     échoue en `agent_prompt_stalled`, car `/clear` ne fait jamais
     passer l'agent en `working`. Le script envoie donc `/clear` sans
     `--wait`, puis attend que `agent_session.value` (id de session
     Claude) change, ce qui signe la fin du `/clear`.
   - Reste à confirmer sur le téléphone : le nom affiché dans Claude
     mobile après `/clear` (le terminal ne montre pas le nom).
2. Nom Remote Control : le tiret cadratin et `~` passent-ils dans
   `--remote-control` et l'affichage Claude mobile ?
   - Côté CLI : `--remote-control "Spike compagnon—main"` est accepté,
     herdr le quote correctement dans le pane. `~` n'est jamais passé
     tel quel (il devient `home`). Affichage mobile à confirmer.
3. `remoteControlAtStartup: true` dans les settings : conflit ou doublon
   avec `--remote-control <nom>` ?
   - Une seule session Remote Control dans le terminal. Absence de
     doublon dans Claude mobile à confirmer.
4. `herdr agent prompt` d'un texte multi-lignes : vérifier que le
   bracketed paste conserve les retours à la ligne dans Claude Code.
   - Levé : un prompt de 5 lignes, dont une vide, avec accents, tiret
     cadratin, guillemets, apostrophe et `$HOME`, arrive intact. Claude
     compte bien 5 lignes et recopie la ligne 4 à l'identique.
5. Format `HERDR-PAIR:1` : couplage à une version du plugin Heeler.
   Épingler la version testée et lancer les vecteurs de test en CI
   locale.
   - Plugin installé : Heeler `f98028b` (v0.1.13, plugin 0.6.0). Le
     submodule est épinglé sur ce commit et les vecteurs sont lus
     depuis le submodule par les tests.
6. HeelerSSH : API publique stable ? Taille du binaire OpenSSL. Plan B :
   Citadel si streamlocal y est supporté.
7. Process détaché via `nohup` en exec SSH : vérifier qu'il survit à la
   fermeture du canal sur macOS (sinon `setsid` ou `launchctl submit`).
   - Levé : `nohup /bin/sh job.sh </dev/null >/dev/null 2>&1 &` en exec
     SSH rend la main en 1 s et le process vit encore 15 s après la
     fermeture du canal, sans recevoir de SIGHUP. Rediriger les trois
     descripteurs est indispensable : sinon sshd attend leur fermeture.
   - Nouveau constat : en exec SSH le PATH ne contient pas
     `/opt/homebrew/bin`, donc pas `herdr`. Le script fixe son PATH.
8. Foundation Models : qualité du nettoyage en français, limite de
   contexte pour une longue dictée.
9. Chemin de `herdr.sock` avec plusieurs sessions herdr nommées.
   - Session par défaut : `~/.config/herdr/herdr.sock`, confirmé (même
     format JSON que la CLI, une requête par connexion). Les sessions
     nommées sont dans `~/.config/herdr/sessions/<nom>/herdr.sock`, non
     gérées dans le MVP.
10. Nouveau : un dossier jamais ouvert par Claude bloque le démarrage
    sur la question « Do you trust this folder? ». `agent start` rend
    alors `agent_not_ready` et l'agent est `blocked`. Le script ne
    répond pas à la place de l'utilisateur : il attend que l'agent
    devienne `idle`, la question se règle sur le Mac.
