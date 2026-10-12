import Foundation
import Testing

@testable import Heraldr

@Suite("Dictation lexicon")
struct DictationLexiconTests {
    private func dictated(_ text: String) -> ComposeView.Origin {
        .dictated(DictatedText(.cleaned(text, raw: text)))
    }

    private func summary(_ lexicon: DictationLexicon) -> [String] {
        lexicon.terms.map { term in ([term.text] + term.variants.map(\.heard)).joined(separator: " ← ") }
    }

    private func temporaryStore() throws -> DictationLexiconStore {
        let directory = FileManager.default.temporaryDirectory.appending(path: "lexicon-\(UUID())")
        let defaults = try #require(UserDefaults(suiteName: "dictation-lexicon-\(UUID())"))
        return DictationLexiconStore(fileURL: directory.appending(path: "dictation-lexicon.json"), defaults: defaults)
    }

    @Test("a short substitution fixed in the preview becomes a term with what was heard")
    func shortSubstitutionIsLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Then git push the branch to origin.",
            origin: dictated("Then on push the branch to origin."))

        #expect(summary(lexicon) == ["git push ← on push"])
        #expect(lexicon.terms.first?.source == .learned)
        #expect(lexicon.vocabulary == ["git push"])
    }

    @Test("a long rewrite of the text is not learned")
    func longRewriteIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Fix the crash at launch when the Mac is unreachable.",
            origin: dictated("So actually we should look into why the app crashes when you start it offline."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("a replacement of more than three words is not learned, even in a barely edited text")
    func longSubstitutionIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Look at the dispatch.sh file in the mac folder of the heraldr project and tell me what is wrong.",
            origin: dictated("Look at the this patch dot s h file in the mac folder of the heraldr project and tell me what is wrong."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("a written or pasted send teaches nothing")
    func writtenOrPastedSendsTeachNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "Then git push the branch.", origin: .written)
        lexicon.learn(sent: "Then git push the branch.", origin: .pasted)

        #expect(lexicon.terms.isEmpty)
    }

    @Test("a dictation sent as is, or only touched up in case and punctuation, teaches nothing")
    func untouchedDictationTeachesNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "then, on push the branch", origin: dictated("Then on push the branch."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("the same mistake fixed again moves to the top without duplicate")
    func repeatedCorrectionIsNotDuplicated() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Then git push the branch.", origin: dictated("Then on push the branch."))
        lexicon.learn(sent: "Open the GitHub file tomorrow.", origin: dictated("Open the guide hub file tomorrow."))

        lexicon.learn(sent: "Then git push to main.", origin: dictated("Then on push to main."))

        #expect(summary(lexicon) == ["git push ← on push", "GitHub ← guide hub"])
        #expect(lexicon.terms.first?.variants.first?.count == 2)
    }

    @Test("another mistake for a known term joins its variants")
    func newVariantJoinsKnownTerm() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Open the Acme dashboard tomorrow morning.", origin: dictated("Open the ack me dashboard tomorrow morning."))

        lexicon.learn(sent: "Restart acme tonight please.", origin: dictated("Restart ac me tonight please."))

        #expect(summary(lexicon) == ["Acme ← ac me ← ack me"])
    }

    @Test("undoing in the preview a replacement made by the code forgets the variant, without learning the reverse")
    func revertedReplacementForgetsVariant() {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me", "ac me"])

        lexicon.learn(
            sent: "Open the ack me dashboard tomorrow morning.",
            origin: dictated("Open the Acme dashboard tomorrow morning."))

        #expect(summary(lexicon) == ["Acme ← ac me"])
    }

    @Test("undoing a single-word replacement also forgets the variant, despite the neighbouring word kept")
    func revertedSingleWordReplacementForgetsVariant() {
        var lexicon = DictationLexicon()
        lexicon.define("GitHub", heard: ["guithub", "guide hub"])

        lexicon.learn(
            sent: "Open the guithub tomorrow morning.",
            origin: dictated("Open the GitHub tomorrow morning."))

        #expect(summary(lexicon) == ["GitHub ← guide hub"])
    }

    @Test("beyond 200 terms, the least recent ones are forgotten")
    func oldestTermsAreForgotten() {
        var lexicon = DictationLexicon()
        for index in 1...205 {
            lexicon.learn(sent: "run term\(index) now", origin: dictated("run error\(index) now"))
        }

        #expect(lexicon.terms.count == 200)
        #expect(lexicon.terms.first?.text == "term205 now")
        #expect(lexicon.terms.last?.text == "term6 now")
    }

    @Test("a correction typed between two dictation bursts is learned on send, only once")
    func correctionBetweenSalvesIsLearnedOnce() {
        var lexicon = DictationLexicon()
        let first = DictatedText(.cleaned("Then on push the branch.", raw: "Then on push the branch."))
        let second = first.appending(
            .cleaned("Then open the pull request.", raw: "Then open the pull request."),
            after: "Then git push the branch.")

        lexicon.learn(sent: second.text, origin: .dictated(second))

        #expect(summary(lexicon) == ["git push ← on push"])
        #expect(lexicon.terms.first?.variants.first?.count == 1)
    }

    @Test("text written before a dictation burst is not taken for a correction")
    func textWrittenBeforeSalveIsNotACorrection() {
        var lexicon = DictationLexicon()
        let dictated = DictatedText(
            .cleaned("Then on push the branch.", raw: "Then on push the branch."),
            after: "Fix the sign-in bug on the login page.")

        lexicon.learn(
            sent: "Fix the sign-in bug on the login page.\nThen git push the branch.",
            origin: .dictated(dictated))

        #expect(summary(lexicon) == ["git push ← on push"])
    }

    @Test("the lexicon survives an app relaunch")
    func lexiconSurvivesRelaunch() throws {
        let store = try temporaryStore()
        var lexicon = DictationLexicon()
        lexicon.learn(
            sent: "Then git push the branch.", origin: dictated("Then on push the branch."),
            at: Date(timeIntervalSince1970: 1_760_000_000))
        lexicon.define("Acme", heard: ["ack me"], at: Date(timeIntervalSince1970: 1_760_000_100))

        store.save(lexicon)

        #expect(store.load() == lexicon)
    }

    @Test("corrections from the old lexicon become terms with their variants, only once")
    func legacyCorrectionsAreMigrated() throws {
        let store = try temporaryStore()
        store.defaults.set(
            Data(
                """
                {"corrections":[
                  {"heard":"ac me","meant":"Acme","count":1,"learnedAt":781000300},
                  {"heard":"on push","meant":"git push","count":3,"learnedAt":781000200},
                  {"heard":"ack me","meant":"acme","count":2,"learnedAt":781000100}
                ]}
                """.utf8), forKey: "dictation-lexicon")

        let migrated = store.load()

        #expect(summary(migrated) == ["Acme ← ac me ← ack me", "git push ← on push"])
        #expect(migrated.terms.flatMap(\.variants).map(\.count) == [1, 2, 3])
        #expect(migrated.terms.allSatisfy { $0.source == .learned })
        #expect(store.defaults.data(forKey: "dictation-lexicon") == nil)
        #expect(store.load() == migrated)
    }

    @Test("a hand-typed term keeps its variants and takes those of another term")
    func typedTermClaimsVariants() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Open the GitHub file tomorrow.", origin: dictated("Open the guide hub file tomorrow."))
        lexicon.learn(sent: "Then git push the branch.", origin: dictated("Then on push the branch."))

        let accepted = lexicon.define("Git Hub", heard: ["  guide hub ", "", "guide hope"])

        #expect(accepted)
        #expect(summary(lexicon) == ["Git Hub ← guide hub ← guide hope", "git push ← on push"])
        #expect(lexicon.terms.first?.source == .typed)
        #expect(lexicon.terms.first?.variants.map(\.source) == [.typed, .typed])
    }

    @Test("editing a term removes the erased variants and keeps the origin of the remaining ones")
    func editingTermKeepsRemainingVariants() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Open the Acme dashboard tomorrow morning.", origin: dictated("Open the ack me dashboard tomorrow morning."))
        lexicon.learn(sent: "Restart acme tonight please.", origin: dictated("Restart ac me tonight please."))

        lexicon.define("Acme", heard: ["ack me", "acne"], replacing: "acme")

        #expect(summary(lexicon) == ["Acme ← ack me ← acne"])
        #expect(lexicon.terms.first?.source == .learned)
        #expect(lexicon.terms.first?.variants.map(\.source) == [.learned, .typed])
    }

    @Test("an empty, too long, or duplicate term or variant is refused")
    func invalidTermIsRejected() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Then git push the branch.", origin: dictated("Then on push the branch."))

        let accepted = [
            lexicon.define("  ", heard: ["on push"]),
            lexicon.define("git push origin main", heard: ["on push"]),
            lexicon.define("git push", heard: ["on push to origin"]),
            lexicon.define("GitHub", heard: ["Github"]),
            lexicon.define("git push", heard: ["on push", "On Push"]),
        ]

        #expect(accepted == [false, false, false, false, false])
        #expect(summary(lexicon) == ["git push ← on push"])
    }

    @Test("a deleted term no longer guides dictation")
    func forgottenTermIsGone() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Then git push the branch.", origin: dictated("Then on push the branch."))

        lexicon.forget(lexicon.terms[0].id)

        #expect(lexicon.terms.isEmpty)
        #expect(lexicon.vocabulary.isEmpty)
    }
}
