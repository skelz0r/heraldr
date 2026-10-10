import Foundation
import Testing
@testable import Heraldr

@Suite("Lexique des corrections de dictée")
struct DictationLexiconTests {
    private func dictated(_ text: String) -> ComposeView.Origin {
        .dictated(.cleaned(text, raw: text))
    }

    @Test("une substitution courte corrigée dans l'aperçu est retenue à l'envoi")
    func shortSubstitutionIsLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Ensuite git push la branche sur origin.",
            origin: dictated("Ensuite on push la branche sur origin."))

        #expect(lexicon.promptLines == ["on push → git push"])
        #expect(lexicon.vocabulary == ["git push"])
    }

    @Test("une réécriture longue du texte n'est pas retenue")
    func longRewriteIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Corrige le crash au lancement quand le Mac est injoignable.",
            origin: dictated("Alors en fait il faudrait regarder pourquoi l'app plante quand on la lance sans réseau."))

        #expect(lexicon.corrections.isEmpty)
    }

    @Test("un remplacement de plus de trois mots n'est pas retenu, même dans un texte peu modifié")
    func longSubstitutionIsNotLearned() {
        var lexicon = DictationLexicon()

        lexicon.learn(
            sent: "Regarde le fichier dispatch.sh dans le dossier mac du projet heraldr et dis-moi ce qui cloche.",
            origin: dictated("Regarde le fichier des pâtes chez le pain dans le dossier mac du projet heraldr et dis-moi ce qui cloche."))

        #expect(lexicon.corrections.isEmpty)
    }

    @Test("un envoi écrit ou collé n'apprend rien")
    func writtenOrPastedSendsTeachNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "Ensuite git push la branche.", origin: .written)
        lexicon.learn(sent: "Ensuite git push la branche.", origin: .pasted)

        #expect(lexicon.corrections.isEmpty)
    }

    @Test("une dictée envoyée telle quelle, ou retouchée seulement en casse et ponctuation, n'apprend rien")
    func untouchedDictationTeachesNothing() {
        var lexicon = DictationLexicon()

        lexicon.learn(sent: "ensuite, on push la branche", origin: dictated("Ensuite on push la branche."))

        #expect(lexicon.corrections.isEmpty)
    }

    @Test("une même erreur corrigée de nouveau remonte en tête sans doublon")
    func repeatedCorrectionIsNotDuplicated() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))
        lexicon.learn(sent: "Ouvre le fichier GitHub demain.", origin: dictated("Ouvre le fichier guide hub demain."))

        lexicon.learn(sent: "Puis git push vers main.", origin: dictated("Puis on push vers main."))

        #expect(lexicon.promptLines == ["on push → git push", "guide hub → GitHub"])
        #expect(lexicon.corrections.first?.count == 2)
    }

    @Test("au-delà de 50 corrections, les plus anciennes sont oubliées")
    func oldestCorrectionsAreForgotten() {
        var lexicon = DictationLexicon()
        for index in 1...55 {
            lexicon.learn(sent: "lance terme\(index) maintenant", origin: dictated("lance erreur\(index) maintenant"))
        }

        #expect(lexicon.corrections.count == 50)
        #expect(lexicon.corrections.first?.meant == "terme55 maintenant")
        #expect(lexicon.corrections.last?.meant == "terme6 maintenant")
    }

    @Test("le lexique survit à la relance de l'app")
    func lexiconSurvivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "dictation-lexicon-\(UUID())"))
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))
        DictationLexiconStore.save(lexicon, to: defaults)

        #expect(DictationLexiconStore.load(from: defaults) == lexicon)
    }
}
