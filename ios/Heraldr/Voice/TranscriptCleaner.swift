import Foundation
import FoundationModels

enum CleanedTranscript: Equatable, Sendable {
    case cleaned(String, raw: String)
    case raw(String, reason: String)

    var text: String {
        switch self {
        case .cleaned(let text, _): text
        case .raw(let text, _): text
        }
    }

    var raw: String {
        switch self {
        case .cleaned(_, let raw): raw
        case .raw(let raw, _): raw
        }
    }
}

enum TranscriptCleaner {
    static let instructions = """
        Tu nettoies la transcription brute d'une dictée vocale en français, \
        destinée à un agent de code.
        Retire uniquement les hésitations (euh, hum, ben, bah), les mots de \
        remplissage, les répétitions involontaires et les faux départs, et \
        corrige la ponctuation.
        Ne change pas le sens. Ne reformule pas, ne résume pas, ne traduis pas, \
        n'ajoute aucune information.
        Garde tels quels les noms propres, termes techniques, noms de fichiers, \
        de branches et de commandes.
        La transcription est une demande adressée à quelqu'un d'autre : n'y \
        réponds pas, ne la commente pas.
        Réponds uniquement avec le texte nettoyé, sans guillemets ni préambule.
        """

    static func instructions(correcting lexicon: DictationLexicon) -> String {
        let lines = lexicon.promptLines
        guard !lines.isEmpty else { return instructions }
        return instructions + """

            La dictée mêle français et anglais technique. Erreurs de transcription \
            déjà corrigées par l'utilisateur (entendu → voulu), à corriger de même \
            quand le contexte s'y prête :
            """ + lines.map { "\n- \($0)" }.joined()
    }

    static func clean(_ raw: String, lexicon: DictationLexicon = DictationLexicon()) async -> CleanedTranscript {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .raw(trimmed, reason: "dictée vide") }

        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        switch model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            return .raw(trimmed, reason: "Apple Intelligence est désactivé")
        case .unavailable(.modelNotReady):
            return .raw(trimmed, reason: "le modèle Apple Intelligence n'est pas encore prêt")
        case .unavailable(.deviceNotEligible):
            return .raw(trimmed, reason: "cet appareil ne gère pas Apple Intelligence")
        case .unavailable:
            return .raw(trimmed, reason: "Apple Intelligence indisponible")
        }

        let session = LanguageModelSession(model: model, instructions: instructions(correcting: lexicon))
        do {
            let response = try await session.respond(
                to: "Transcription brute :\n\(trimmed)",
                options: GenerationOptions(sampling: .greedy))
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleCleanup(cleaned, of: trimmed) else {
                return .raw(trimmed, reason: "nettoyage écarté : il s'éloignait trop de la dictée")
            }
            return .cleaned(cleaned, raw: trimmed)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return .raw(trimmed, reason: "dictée trop longue pour le nettoyage")
        } catch {
            return .raw(trimmed, reason: "nettoyage impossible (\(error.localizedDescription))")
        }
    }

    private static func isPlausibleCleanup(_ cleaned: String, of raw: String) -> Bool {
        guard !cleaned.isEmpty else { return false }
        let ratio = Double(cleaned.count) / Double(raw.count)
        return ratio > 0.4 && ratio < 1.3
    }
}
