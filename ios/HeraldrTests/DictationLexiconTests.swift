import Foundation
import Testing

@testable import Heraldr

@Suite("Lexique de dictée")
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

    @Test("une substitution courte corrigée dans l'aperçu devient un terme avec ce qui avait été entendu")
    func shortSubstitutionIsLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Ensuite git push la branche sur origin.",
            origin: dictated("Ensuite on push la branche sur origin."))

        #expect(summary(lexicon) == ["git push ← on push"])
        #expect(lexicon.terms.first?.source == .learned)
        #expect(lexicon.vocabulary == ["git push"])
    }

    @Test("une réécriture longue du texte n'est pas retenue")
    func longRewriteIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Corrige le crash au lancement quand le Mac est injoignable.",
            origin: dictated("Alors en fait il faudrait regarder pourquoi l'app plante quand on la lance sans réseau."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("un remplacement de plus de trois mots n'est pas retenu, même dans un texte peu modifié")
    func longSubstitutionIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Regarde le fichier dispatch.sh dans le dossier mac du projet heraldr et dis-moi ce qui cloche.",
            origin: dictated("Regarde le fichier des pâtes chez le pain dans le dossier mac du projet heraldr et dis-moi ce qui cloche."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("un envoi écrit ou collé n'apprend rien")
    func writtenOrPastedSendsTeachNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "Ensuite git push la branche.", origin: .written)
        lexicon.learn(sent: "Ensuite git push la branche.", origin: .pasted)

        #expect(lexicon.terms.isEmpty)
    }

    @Test("une dictée envoyée telle quelle, ou retouchée seulement en casse et ponctuation, n'apprend rien")
    func untouchedDictationTeachesNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "ensuite, on push la branche", origin: dictated("Ensuite on push la branche."))

        #expect(lexicon.terms.isEmpty)
    }

    @Test("une même erreur corrigée de nouveau remonte en tête sans doublon")
    func repeatedCorrectionIsNotDuplicated() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))
        lexicon.learn(sent: "Ouvre le fichier GitHub demain.", origin: dictated("Ouvre le fichier guide hub demain."))

        lexicon.learn(sent: "Puis git push vers main.", origin: dictated("Puis on push vers main."))

        #expect(summary(lexicon) == ["git push ← on push", "GitHub ← guide hub"])
        #expect(lexicon.terms.first?.variants.first?.count == 2)
    }

    @Test("une autre erreur pour un terme connu s'ajoute à ses variantes")
    func newVariantJoinsKnownTerm() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ouvre le tableau de bord de Acme demain matin.", origin: dictated("Ouvre le tableau de bord de ack me demain matin."))

        lexicon.learn(sent: "Relance acme ce soir.", origin: dictated("Relance ak me ce soir."))

        #expect(summary(lexicon) == ["Acme ← ak me ← ack me"])
    }

    @Test("revenir dans l'aperçu sur un remplacement fait par le code oublie la variante, sans apprendre l'inverse")
    func revertedReplacementForgetsVariant() {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me", "ak me"])

        lexicon.learn(
            sent: "Ouvre le tableau de bord de ack me demain matin.",
            origin: dictated("Ouvre le tableau de bord de Acme demain matin."))

        #expect(summary(lexicon) == ["Acme ← ak me"])
    }

    @Test("revenir sur le remplacement d'un seul mot oublie aussi la variante, malgré le mot voisin retenu")
    func revertedSingleWordReplacementForgetsVariant() {
        var lexicon = DictationLexicon()
        lexicon.define("GitHub", heard: ["guithub", "guide hub"])

        lexicon.learn(
            sent: "Ouvre le guithub demain matin.",
            origin: dictated("Ouvre le GitHub demain matin."))

        #expect(summary(lexicon) == ["GitHub ← guide hub"])
    }

    @Test("au-delà de 200 termes, les moins récents sont oubliés")
    func oldestTermsAreForgotten() {
        var lexicon = DictationLexicon()
        for index in 1...205 {
            lexicon.learn(sent: "lance terme\(index) maintenant", origin: dictated("lance erreur\(index) maintenant"))
        }

        #expect(lexicon.terms.count == 200)
        #expect(lexicon.terms.first?.text == "terme205 maintenant")
        #expect(lexicon.terms.last?.text == "terme6 maintenant")
    }

    @Test("une correction tapée entre deux salves est retenue à l'envoi, une seule fois")
    func correctionBetweenSalvesIsLearnedOnce() {
        var lexicon = DictationLexicon()
        let first = DictatedText(.cleaned("Ensuite on push la branche.", raw: "Ensuite on push la branche."))
        let second = first.appending(
            .cleaned("Puis ouvre la pull request.", raw: "Puis ouvre la pull request."),
            after: "Ensuite git push la branche.")

        lexicon.learn(sent: second.text, origin: .dictated(second))

        #expect(summary(lexicon) == ["git push ← on push"])
        #expect(lexicon.terms.first?.variants.first?.count == 1)
    }

    @Test("le texte écrit avant une salve n'est pas pris pour une correction")
    func textWrittenBeforeSalveIsNotACorrection() {
        var lexicon = DictationLexicon()
        let dictated = DictatedText(
            .cleaned("Ensuite on push la branche.", raw: "Ensuite on push la branche."),
            after: "Corrige le bug de connexion sur la page de login.")

        lexicon.learn(
            sent: "Corrige le bug de connexion sur la page de login.\nEnsuite git push la branche.",
            origin: .dictated(dictated))

        #expect(summary(lexicon) == ["git push ← on push"])
    }

    @Test("le lexique survit à la relance de l'app")
    func lexiconSurvivesRelaunch() throws {
        let store = try temporaryStore()
        var lexicon = DictationLexicon()
        lexicon.learn(
            sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."),
            at: Date(timeIntervalSince1970: 1_760_000_000))
        lexicon.define("Acme", heard: ["ack me"], at: Date(timeIntervalSince1970: 1_760_000_100))

        store.save(lexicon)

        #expect(store.load() == lexicon)
    }

    @Test("les corrections de l'ancien lexique deviennent des termes avec leurs variantes, une seule fois")
    func legacyCorrectionsAreMigrated() throws {
        let store = try temporaryStore()
        store.defaults.set(
            Data(
                """
                {"corrections":[
                  {"heard":"ak me","meant":"Acme","count":1,"learnedAt":781000300},
                  {"heard":"on push","meant":"git push","count":3,"learnedAt":781000200},
                  {"heard":"ack me","meant":"acme","count":2,"learnedAt":781000100}
                ]}
                """.utf8), forKey: "dictation-lexicon")

        let migrated = store.load()

        #expect(summary(migrated) == ["Acme ← ak me ← ack me", "git push ← on push"])
        #expect(migrated.terms.flatMap(\.variants).map(\.count) == [1, 2, 3])
        #expect(migrated.terms.allSatisfy { $0.source == .learned })
        #expect(store.defaults.data(forKey: "dictation-lexicon") == nil)
        #expect(store.load() == migrated)
    }

    @Test("un terme saisi à la main garde ses variantes et prend celles d'un autre terme")
    func typedTermClaimsVariants() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ouvre le fichier GitHub demain.", origin: dictated("Ouvre le fichier guide hub demain."))
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        let accepted = lexicon.define("Git Hub", heard: ["  guide hub ", "", "guide hope"])

        #expect(accepted)
        #expect(summary(lexicon) == ["Git Hub ← guide hub ← guide hope", "git push ← on push"])
        #expect(lexicon.terms.first?.source == .typed)
        #expect(lexicon.terms.first?.variants.map(\.source) == [.typed, .typed])
    }

    @Test("modifier un terme retire les variantes effacées et garde l'origine de celles qui restent")
    func editingTermKeepsRemainingVariants() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ouvre le tableau de bord de Acme demain matin.", origin: dictated("Ouvre le tableau de bord de ack me demain matin."))
        lexicon.learn(sent: "Relance acme ce soir.", origin: dictated("Relance ak me ce soir."))

        lexicon.define("Acme", heard: ["ack me", "ak mee"], replacing: "acme")

        #expect(summary(lexicon) == ["Acme ← ack me ← ak mee"])
        #expect(lexicon.terms.first?.source == .learned)
        #expect(lexicon.terms.first?.variants.map(\.source) == [.learned, .typed])
    }

    @Test("un terme ou une variante vide, trop longue, ou identique à une autre est refusé")
    func invalidTermIsRejected() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        let accepted = [
            lexicon.define("  ", heard: ["on push"]),
            lexicon.define("git push origin main", heard: ["on push"]),
            lexicon.define("git push", heard: ["on pousse vers origin"]),
            lexicon.define("GitHub", heard: ["Github"]),
            lexicon.define("git push", heard: ["on push", "On Push"]),
        ]

        #expect(accepted == [false, false, false, false, false])
        #expect(summary(lexicon) == ["git push ← on push"])
    }

    @Test("un terme supprimé ne guide plus la dictée")
    func forgottenTermIsGone() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        lexicon.forget(lexicon.terms[0].id)

        #expect(lexicon.terms.isEmpty)
        #expect(lexicon.vocabulary.isEmpty)
    }
}
