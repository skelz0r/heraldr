import Foundation

enum PromptEnvelope {
    static func wrap(_ text: String) -> String {
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
}
