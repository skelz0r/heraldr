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

## Spike des notifications push

Spike du 2026-10-10 (herdr 0.9.3, Claude Code 2.1.296, Node 25), avant
d'écrire les push des questions des agents `-main`.

11. URL de la session Remote Control d'un agent, récupérable côté Mac ?
    - Levé : `~/.claude/sessions/<pid>.json` porte le `sessionId` de la
      session Claude, celui que herdr expose dans
      `agent_session.value`, et son `bridgeSessionId`
      (`session_01…`). L'URL est
      `https://claude.ai/code/<bridgeSessionId>`, celle qu'affiche
      `/remote-control`.
    - `claude.ai/code/*` est un universal link de l'app Claude
      (`apple-app-site-association` de claude.ai, appID
      `Q6L2SF6YDW.com.anthropic.claude`) : Heraldr l'ouvre avec
      `universalLinksOnly`, et se rabat sur un bouton « Ouvrir dans
      Claude » si l'app ne le prend pas.
    - Le texte de la question est dans le transcript
      `~/.claude/projects/<cwd encodé>/<sessionId>.jsonl` : dernier
      `tool_use` `AskUserQuestion` d'un message `assistant`,
      `input.questions[0].question`. Pour une permission, le dernier
      `tool_use` donne le nom de l'outil.
12. Passage en `blocked` sans daemon ?
    - Levé : un plugin herdr déclare
      `[[events]] on = "pane.agent_status_changed"` ; herdr lance un
      process court par changement d'état avec
      `HERDR_PLUGIN_EVENT_JSON` (`pane_id`, `workspace_id`,
      `agent_status`). Le nom de l'agent n'y est pas : il vient de
      `herdr agent get <pane>`, qui sert aussi à revérifier l'état après
      le debounce. `herdr plugin link` enregistre un plugin local sans
      build.
13. Envoi APNs HTTP/2 depuis le Mac ?
    - Levé : Node (déjà requis par le plugin Heeler) signe le JWT ES256
      avec `node:crypto` (`dsaEncoding: "ieee-p1363"`) et poste avec
      `node:http2`, sans dépendance. curl 8.7.1 du système a aussi
      nghttp2, mais signer en ES256 en shell est pénible.
    - La clé `.p8` APNs de local_events (`KEYID67890`, équipe
      `ABCDE12345`) passe l'authentification pour le topic
      `com.skelz0r.heraldr.dev` : sandbox et production répondent
      `BadDeviceToken` à un faux token, et non `InvalidProviderToken`.
      Une clé APNs vaut pour toutes les apps de l'équipe.
    - Vérifié sur l'iPhone : une question AskUserQuestion de
      `home-main` produit la notif (label, agent, question), et le tap
      ouvre la session dans l'app Claude.
    - `herdr plugin link` refuse `--enabled` suivi d'un chemin
      (`unknown option`) ; le plugin lié est activé par défaut.
    - Piège : `~/.private_keys/AuthKey_KEYID12345.p8` est une clé App
      Store Connect API, refusée par APNs (`InvalidProviderToken`).
