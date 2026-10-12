import Foundation
import FoundationModels

struct CleaningTrace: Equatable, Sendable {
    struct Hint: Codable, Equatable, Sendable {
        let heard: String
        let term: String
        let applied: Bool
    }

    let replaced: String
    let replacements: [DictationLexicon.Replacement]
    let hints: [Hint]
}

enum CleanedTranscript: Equatable, Sendable {
    case cleaned(String, raw: String, trace: CleaningTrace? = nil)
    case raw(String, original: String, reason: String, trace: CleaningTrace? = nil)

    var text: String {
        switch self {
        case .cleaned(let text, _, _): text
        case .raw(let text, _, _, _): text
        }
    }

    var raw: String {
        switch self {
        case .cleaned(_, let raw, _): raw
        case .raw(_, let original, _, _): original
        }
    }

    var reason: String? {
        if case .raw(_, _, let reason, _) = self { reason } else { nil }
    }

    var trace: CleaningTrace? {
        switch self {
        case .cleaned(_, _, let trace): trace
        case .raw(_, _, _, let trace): trace
        }
    }
}

struct CleaningModel: Sendable {
    enum Reply: Sendable {
        case text(String)
        case failed(reason: String)
    }

    let reply: @Sendable (_ instructions: String, _ prompt: String) async -> Reply

    static let onDevice = CleaningModel { instructions, prompt in
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        switch model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            return .failed(reason: "Apple Intelligence est désactivé")
        case .unavailable(.modelNotReady):
            return .failed(reason: "le modèle Apple Intelligence n'est pas encore prêt")
        case .unavailable(.deviceNotEligible):
            return .failed(reason: "cet appareil ne gère pas Apple Intelligence")
        case .unavailable:
            return .failed(reason: "Apple Intelligence indisponible")
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
            return .text(response.content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return .failed(reason: "dictée trop longue pour le nettoyage")
        } catch {
            return .failed(reason: "nettoyage impossible (\(error.localizedDescription))")
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

    static func instructions(hinting hints: [(heard: String, term: String)]) -> String {
        guard !hints.isEmpty else { return instructions }
        return instructions + """

            La dictée mêle français et anglais technique. Dans cette transcription, \
            ces mots sont peut-être mal entendus ; remplace-les seulement si la \
            phrase n'a pas de sens autrement :
            """ + hints.map { "\n- « \($0.heard) » veut peut-être dire « \($0.term) »" }.joined()
    }

    static func clean(_ raw: String, lexicon: DictationLexicon = DictationLexicon(), model: CleaningModel = .onDevice) async -> CleanedTranscript {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .raw(trimmed, original: trimmed, reason: "dictée vide") }

        let before = lexicon.replacements(in: trimmed)
        let corrected = before.text
        let hints = lexicon.hints(for: corrected)
        func trace(reply: String?, after: [DictationLexicon.Replacement] = []) -> CleaningTrace {
            CleaningTrace(
                replaced: corrected,
                replacements: before.applied + after,
                hints: hints.map { hint in
                    let applied =
                        reply.map {
                            !DictationLexicon.contains(hint.heard, in: $0) && DictationLexicon.contains(hint.term, in: $0)
                        } ?? false
                    return CleaningTrace.Hint(heard: hint.heard, term: hint.term, applied: applied)
                })
        }
        switch await model.reply(instructions(hinting: hints), "Transcription brute :\n\(corrected)") {
        case .failed(let reason):
            return .raw(corrected, original: trimmed, reason: reason, trace: trace(reply: nil))
        case .text(let reply):
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleCleanup(cleaned, of: corrected) else {
                return .raw(corrected, original: trimmed, reason: "nettoyage écarté : il s'éloignait trop de la dictée", trace: trace(reply: nil))
            }
            let after = lexicon.replacements(in: cleaned)
            return .cleaned(after.text, raw: trimmed, trace: trace(reply: cleaned, after: after.applied))
        }
    }

    private static func isPlausibleCleanup(_ cleaned: String, of raw: String) -> Bool {
        guard !cleaned.isEmpty else { return false }
        let ratio = Double(cleaned.count) / Double(raw.count)
        return ratio > 0.4 && ratio < 1.3
    }
}
