import Foundation

enum PromptEnvelope {
    static func wrap(_ text: String, for workspace: Workspace) -> String {
        workspace.isHome ? home(text) : standard(text)
    }

    private static func standard(_ text: String) -> String {
        """
        Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : \
        attention aux erreurs de transcription).

        \(text.trimmingCharacters(in: .whitespacesAndNewlines))

        Consignes :
        - explore le code pour comprendre la demande, ne modifie rien ici
        - si la demande est ambiguë, pose tes questions avec AskUserQuestion
        - termine obligatoirement en dispatchant le travail avec /start
        """
    }

    private static func home(_ text: String) -> String {
        """
        Demande envoyée depuis l'iPhone vers Home, la cible par défaut de \
        l'app (peut venir d'une dictée vocale : attention aux erreurs de \
        transcription).

        \(text.trimmingCharacters(in: .whitespacesAndNewlines))

        Consignes :
        - ne modifie rien ici
        - identifie le projet visé parmi les workspaces herdr ouverts : \
        labels avec `herdr workspace list`, dossiers avec \
        `herdr pane list --workspace <workspace_id>` (cwd)
        - si plusieurs projets peuvent correspondre, pose la question avec \
        AskUserQuestion avant tout relais
        - si un projet est visé, relaie-lui la demande puis arrête-toi, sans \
        /start : `/bin/sh "$HOME/.local/state/heraldr/dispatch.sh" relay \
        <workspace_id>` avec sur l'entrée standard la demande d'origine, \
        corrigée des erreurs de transcription évidentes et complétée des \
        réponses à tes questions
        - si aucun projet ouvert n'est concerné : explore ce qu'il faut pour \
        comprendre la demande, pose tes questions avec AskUserQuestion si \
        elle est ambiguë et termine obligatoirement en dispatchant le \
        travail avec /start
        """
    }
}
