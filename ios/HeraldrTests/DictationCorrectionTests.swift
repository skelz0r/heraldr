import Foundation
import Testing
@testable import Heraldr

@Suite("Correction d'une dictée par le lexique")
struct DictationCorrectionTests {
    private actor Recorder {
        var instructions: [String] = []

        func record(_ text: String) {
            instructions.append(text)
        }
    }

    private static let unchanged = CleaningModel { _, prompt in
        .text(String(prompt.dropFirst("Transcription brute :\n".count)))
    }

    private static func answering(_ text: String) -> CleaningModel {
        CleaningModel { _, _ in .text(text) }
    }

    private static let unavailable = CleaningModel { _, _ in .failed(reason: "Apple Intelligence est désactivé") }

    private func learned(_ pairs: [(proposed: String, sent: String)]) -> DictationLexicon {
        var lexicon = DictationLexicon()
        for pair in pairs {
            lexicon.learn(sent: pair.sent, origin: .dictated(DictatedText(.cleaned(pair.proposed, raw: pair.proposed))))
        }
        return lexicon
    }

    private let acme = (
        proposed: "Ouvre le tableau de bord de ack me demain matin.",
        sent: "Ouvre le tableau de bord de Acme demain matin.")

    @Test("« ack me » dicté donne « Acme » dans le texte proposé, quelle que soit la sortie du modèle")
    func knownVariantIsAlwaysReplaced() async {
        let lexicon = learned([acme])
        let raw = "Envoie la facture à ack me ce soir"

        let outcomes = [
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.unchanged),
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.answering("Envoie la facture à ack me ce soir.")),
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.unavailable),
        ]

        #expect(outcomes.map(\.text) == [
            "Envoie la facture à Acme ce soir",
            "Envoie la facture à Acme ce soir.",
            "Envoie la facture à Acme ce soir",
        ])
        #expect(outcomes.map(\.raw) == [raw, raw, raw])
    }

    @Test("une variante apprise d'un seul mot n'est jamais remplacée d'office : elle est seulement signalée au nettoyage")
    func learnedSingleWordIsOnlyHinted() async {
        let lexicon = learned([(proposed: "Ouvre le guithub du projet ce soir.", sent: "Ouvre le git hub du projet ce soir.")])
        let recorder = Recorder()
        let model = CleaningModel { instructions, prompt in
            await recorder.record(instructions)
            return .text(String(prompt.dropFirst("Transcription brute :\n".count)))
        }

        let cleaned = await TranscriptCleaner.clean("Regarde le guithub", lexicon: lexicon, model: model)

        #expect(cleaned.text == "Regarde le guithub")
        #expect(await recorder.instructions.first?.hasSuffix("\n- « guithub » veut peut-être dire « git hub »") == true)
    }

    @Test("le nettoyage ne reçoit que trois variantes au plus, celles entendues dans la dictée")
    func onlyHeardVariantsAreHinted() async {
        let lexicon = learned(["alpha", "bravo", "charlie", "delta", "echo"].map { word in
            (proposed: "Lance \(word)x vers la prod ce soir.", sent: "Lance \(word) one vers la prod ce soir.")
        })
        let recorder = Recorder()
        let model = CleaningModel { instructions, _ in
            await recorder.record(instructions)
            return .text("texte")
        }

        _ = await TranscriptCleaner.clean("Rien de connu ici", lexicon: lexicon, model: model)
        _ = await TranscriptCleaner.clean("alphax bravox charliex deltax", lexicon: lexicon, model: model)

        let instructions = await recorder.instructions
        #expect(instructions.first == TranscriptCleaner.instructions)
        #expect(instructions.last?.components(separatedBy: "\n- ").count == 4)
        #expect(instructions.last?.contains("echox") == false)
    }

    @Test("une variante n'est pas remplacée à l'intérieur d'un mot plus long")
    func variantInsideLongerWordIsKept() async {
        var lexicon = learned([acme])
        lexicon.define("Docu", heard: ["doc"])

        let cleaned = await TranscriptCleaner.clean(
            "Lis la doc et la documentation du ack mete", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Lis la Docu et la documentation du ack mete")
    }

    @Test("la casse du terme est gardée, quelle que soit celle de la dictée")
    func termCaseIsKept() async {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me"])

        let cleaned = await TranscriptCleaner.clean(
            "acme, puis ack me.", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Acme, puis Acme.")
    }

    @Test("la variante la plus longue l'emporte sur une plus courte qu'elle contient")
    func longestVariantWins() async {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ak me"])
        lexicon.define("Docu", heard: ["doc"])

        let cleaned = await TranscriptCleaner.clean("Ouvre le ak me et la doc", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Ouvre le Acme et la Docu")
    }
}
