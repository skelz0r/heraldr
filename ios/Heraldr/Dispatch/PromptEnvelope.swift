import Foundation

enum PromptEnvelope {
    static func wrap(_ text: String, attachments: [String] = [], for workspace: Workspace) -> String {
        let request = request(text, attachments: attachments)
        return workspace.isHome ? home(request) : standard(request)
    }

    static func forTab(_ text: String, attachments: [String] = []) -> String {
        """
        Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : \
        attention aux erreurs de transcription).

        \(request(text, attachments: attachments))
        """
    }

    private static func request(_ text: String, attachments: [String]) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return text }
        let paths = attachments.map { "- \($0)" }.joined(separator: "\n")
        return "\(text)\n\nCaptures d'écran jointes, à lire avec Read :\n\(paths)"
    }

    private static func standard(_ request: String) -> String {
        """
        Demande envoyée depuis l'iPhone (peut venir d'une dictée vocale : \
        attention aux erreurs de transcription).

        \(request)

        Consignes :
        - explore le code pour comprendre la demande, ne modifie rien ici
        - si la demande est ambiguë, pose tes questions avec AskUserQuestion
        - termine obligatoirement en dispatchant le travail avec /start
        """
    }

    private static func home(_ request: String) -> String {
        """
        Demande envoyée depuis l'iPhone vers Home, la cible par défaut de \
        l'app (peut venir d'une dictée vocale : attention aux erreurs de \
        transcription).

        \(request)

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
        corrigée des erreurs de transcription évidentes, complétée des \
        réponses à tes questions et suivie des chemins des captures jointes \
        s'il y en a
        - si aucun projet ouvert n'est concerné : explore ce qu'il faut pour \
        comprendre la demande, pose tes questions avec AskUserQuestion si \
        elle est ambiguë et termine obligatoirement en dispatchant le \
        travail avec /start
        """
    }
}
