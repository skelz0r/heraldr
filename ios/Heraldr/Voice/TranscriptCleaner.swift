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
            return .failed(reason: "Apple Intelligence is turned off")
        case .unavailable(.modelNotReady):
            return .failed(reason: "the Apple Intelligence model is not ready yet")
        case .unavailable(.deviceNotEligible):
            return .failed(reason: "this device does not support Apple Intelligence")
        case .unavailable:
            return .failed(reason: "Apple Intelligence unavailable")
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy))
            return .text(response.content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return .failed(reason: "dictation too long to clean up")
        } catch {
            return .failed(reason: "cleanup failed (\(error.localizedDescription))")
        }
    }
}

enum TranscriptCleaner {
    static let instructions = """
        You clean up the raw transcript of a voice dictation meant for a \
        coding agent.
        Keep the language of the transcript: never translate it, and answer \
        in that same language.
        Only remove hesitations (uh, um, er, or their equivalent in the \
        transcript's language), filler words, unintended repetitions and \
        false starts, and fix the punctuation.
        Do not change the meaning. Do not rephrase, summarize or add any \
        information.
        Keep proper nouns, technical terms, and file, branch and command \
        names as they are.
        The transcript is a request addressed to someone else: do not answer \
        it or comment on it.
        Reply only with the cleaned text, without quotes or preamble.
        """

    static func instructions(hinting hints: [(heard: String, term: String)]) -> String {
        guard !hints.isEmpty else { return instructions }
        return instructions + """

            The dictation may mix its language with technical English. In \
            this transcript, these words may have been misheard; replace them \
            only if the sentence makes no sense otherwise:
            """ + hints.map { "\n- \"\($0.heard)\" may mean \"\($0.term)\"" }.joined()
    }

    static func clean(_ raw: String, lexicon: DictationLexicon = DictationLexicon(), model: CleaningModel = .onDevice) async -> CleanedTranscript {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .raw(trimmed, original: trimmed, reason: "empty dictation") }

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
        switch await model.reply(instructions(hinting: hints), "Raw transcript:\n\(corrected)") {
        case .failed(let reason):
            return .raw(corrected, original: trimmed, reason: reason, trace: trace(reply: nil))
        case .text(let reply):
            let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleCleanup(cleaned, of: corrected) else {
                return .raw(corrected, original: trimmed, reason: "cleanup discarded: it strayed too far from the dictation", trace: trace(reply: nil))
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
