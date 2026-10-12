import Foundation
import Testing

@testable import Heraldr

@Suite("Dictation corrected by the lexicon")
struct DictationCorrectionTests {
    private actor Recorder {
        var instructions: [String] = []

        func record(_ text: String) {
            instructions.append(text)
        }
    }

    private static let unchanged = CleaningModel { _, prompt in
        .text(String(prompt.dropFirst("Raw transcript:\n".count)))
    }

    private static func answering(_ text: String) -> CleaningModel {
        CleaningModel { _, _ in .text(text) }
    }

    private static let unavailable = CleaningModel { _, _ in .failed(reason: "Apple Intelligence is turned off") }

    private func learned(_ pairs: [(proposed: String, sent: String)]) -> DictationLexicon {
        var lexicon = DictationLexicon()
        for pair in pairs {
            lexicon.learn(sent: pair.sent, origin: .dictated(DictatedText(.cleaned(pair.proposed, raw: pair.proposed))))
        }
        return lexicon
    }

    private let acme = (
        proposed: "Open the ack me dashboard tomorrow morning.",
        sent: "Open the Acme dashboard tomorrow morning."
    )

    @Test("dictated \"ack me\" gives \"Acme\" in the proposed text, whatever the model output")
    func knownVariantIsAlwaysReplaced() async {
        let lexicon = learned([acme])
        let raw = "Send the invoice to ack me tonight"

        let outcomes = [
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.unchanged),
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.answering("Send the invoice to ack me tonight.")),
            await TranscriptCleaner.clean(raw, lexicon: lexicon, model: Self.unavailable),
        ]

        #expect(
            outcomes.map(\.text) == [
                "Send the invoice to Acme tonight",
                "Send the invoice to Acme tonight.",
                "Send the invoice to Acme tonight",
            ])
        #expect(outcomes.map(\.raw) == [raw, raw, raw])
    }

    @Test("a learned single-word variant is never replaced outright: it is only hinted to the cleanup")
    func learnedSingleWordIsOnlyHinted() async {
        let lexicon = learned([(proposed: "Open the guithub of the project tonight.", sent: "Open the git hub of the project tonight.")])
        let recorder = Recorder()
        let model = CleaningModel { instructions, prompt in
            await recorder.record(instructions)
            return .text(String(prompt.dropFirst("Raw transcript:\n".count)))
        }

        let cleaned = await TranscriptCleaner.clean("Look at the guithub", lexicon: lexicon, model: model)

        #expect(cleaned.text == "Look at the guithub")
        #expect(await recorder.instructions.first?.hasSuffix("\n- \"guithub\" may mean \"git hub\"") == true)
    }

    @Test("the cleanup gets three variants at most, those heard in the dictation")
    func onlyHeardVariantsAreHinted() async {
        let lexicon = learned(
            ["alpha", "bravo", "charlie", "delta", "echo"].map { word in
                (proposed: "Ship \(word)x to prod tonight please.", sent: "Ship \(word) one to prod tonight please.")
            })
        let recorder = Recorder()
        let model = CleaningModel { instructions, _ in
            await recorder.record(instructions)
            return .text("text")
        }

        _ = await TranscriptCleaner.clean("Nothing known here", lexicon: lexicon, model: model)
        _ = await TranscriptCleaner.clean("alphax bravox charliex deltax", lexicon: lexicon, model: model)

        let instructions = await recorder.instructions
        #expect(instructions.first == TranscriptCleaner.instructions)
        #expect(instructions.last?.components(separatedBy: "\n- ").count == 4)
        #expect(instructions.last?.contains("echox") == false)
    }

    @Test("a variant is not replaced inside a longer word")
    func variantInsideLongerWordIsKept() async {
        var lexicon = learned([acme])
        lexicon.define("Docs", heard: ["doc"])

        let cleaned = await TranscriptCleaner.clean(
            "Read the doc and the documentation of the ack meter", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Read the Docs and the documentation of the ack meter")
    }

    @Test("the case of the term is kept, whatever the case of the dictation")
    func termCaseIsKept() async {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me"])

        let cleaned = await TranscriptCleaner.clean(
            "acme, then Ack Me.", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Acme, then Acme.")
    }

    @Test("the longest variant wins over a shorter one it contains")
    func longestVariantWins() async {
        var lexicon = DictationLexicon()
        lexicon.define("AcmeDocs", heard: ["ack me doc"])
        lexicon.define("Docs", heard: ["doc"])

        let cleaned = await TranscriptCleaner.clean("Open the ack me doc and the doc", lexicon: lexicon, model: Self.unavailable)

        #expect(cleaned.text == "Open the AcmeDocs and the Docs")
    }
}
