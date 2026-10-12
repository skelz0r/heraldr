import Foundation
import Testing
@testable import Heraldr

@Suite("Lexique des corrections de dictée")
struct DictationLexiconTests {
    private func dictated(_ text: String) -> ComposeView.Origin {
        .dictated(DictatedText(.cleaned(text, raw: text)))
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

    @Test("une correction tapée entre deux salves est retenue à l'envoi, une seule fois")
    func correctionBetweenSalvesIsLearnedOnce() {
        var lexicon = DictationLexicon()
        let first = DictatedText(.cleaned("Ensuite on push la branche.", raw: "Ensuite on push la branche."))
        let second = first.appending(
            .cleaned("Puis ouvre la pull request.", raw: "Puis ouvre la pull request."),
            after: "Ensuite git push la branche.")

        lexicon.learn(sent: second.text, origin: .dictated(second))

        #expect(lexicon.promptLines == ["on push → git push"])
        #expect(lexicon.corrections.first?.count == 1)
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

        #expect(lexicon.promptLines == ["on push → git push"])
    }

    @Test("le lexique survit à la relance de l'app")
    func lexiconSurvivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "dictation-lexicon-\(UUID())"))
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))
        DictationLexiconStore.save(lexicon, to: defaults)

        #expect(DictationLexiconStore.load(from: defaults) == lexicon)
    }

    @Test("le nettoyage reçoit les corrections apprises, et rien de plus quand le lexique est vide")
    func cleanerInstructionsCarryCorrections() {
        var lexicon = DictationLexicon()
        #expect(TranscriptCleaner.instructions(correcting: lexicon) == TranscriptCleaner.instructions)

        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        #expect(TranscriptCleaner.instructions(correcting: lexicon).hasSuffix("\n- on push → git push"))
    }

    @Test("une correction ajoutée à la main pour une erreur connue la remplace et remonte en tête")
    func manualCorrectionReplacesKnownHeard() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))
        lexicon.learn(sent: "Ouvre le fichier GitHub demain.", origin: dictated("Ouvre le fichier guide hub demain."))

        let accepted = lexicon.correct(heard: "On Push", meant: "git pull")

        #expect(accepted)

        #expect(lexicon.promptLines == ["On Push → git pull", "guide hub → GitHub"])
    }

    @Test("modifier l'entendu d'une correction oublie l'ancien")
    func editingHeardForgetsOriginal() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        lexicon.correct(heard: "on pousse", meant: "git push", replacing: "on push")

        #expect(lexicon.promptLines == ["on pousse → git push"])
    }

    @Test("une correction vide, trop longue ou identique à l'entendu est refusée")
    func invalidManualCorrectionIsRejected() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        let accepted = [
            lexicon.correct(heard: "  ", meant: "git push"),
            lexicon.correct(heard: "on push", meant: "git push origin main"),
            lexicon.correct(heard: "Github", meant: "GitHub"),
            lexicon.correct(heard: "on push", meant: "", replacing: "on push"),
        ]

        #expect(accepted == [false, false, false, false])

        #expect(lexicon.promptLines == ["on push → git push"])
    }

    @Test("une correction supprimée ne guide plus la dictée")
    func forgottenCorrectionIsGone() {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ensuite git push la branche.", origin: dictated("Ensuite on push la branche."))

        lexicon.forget(heard: "On Push")

        #expect(lexicon.corrections.isEmpty)
    }
}
