import XCTest

@MainActor
final class SheetsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHistoriqueTachesEtQuestions() {
        let app = launch("history")
        element("home.history", in: app).tap()
        waitFor(app.staticTexts["Ajoute un mode sombre à l'écran de réglages et vérifie le contraste des pastilles"])
        app.navigationBars["Historique"].swipeUp()
        XCTAssertTrue(app.staticTexts["2 captures jointes"].exists)
        XCTAssertTrue(app.staticTexts["Heraldr — harness-qa"].exists)
        capture("historique-taches", in: app)
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["l'agent acme-main appartient au workspace wM"].exists)
        XCTAssertTrue(app.staticTexts["1 capture jointe"].exists)
        XCTAssertTrue(app.staticTexts["Envoi interrompu avant la réponse du Mac."].exists)
        capture("historique-echecs", in: app)

        app.buttons["Questions"].tap()
        waitFor(app.staticTexts["Le cache est vidé à chaque déploiement."])
        capture("historique-questions", in: app)
        app.staticTexts["Comment marche le cache des vignettes ?"].tap()
        waitFor(app.staticTexts["Le cache des vignettes vit dans tmp/thumbnails."])
        capture("reponse", in: app)
    }

    func testCopierPuisRenvoyer() {
        let app = launch("history")
        element("home.history", in: app).tap()
        let copy = element("history.copy", in: app)
        waitFor(copy)
        copy.tap()
        XCTAssertTrue(app.buttons["Copié"].waitForExistence(timeout: 2))
        capture("historique-copie", in: app, dark: false)

        element("history.resend", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Heraldr"), notice.label)
    }

    func testHistoriqueVide() {
        let app = launch("demo")
        element("home.history", in: app).tap()
        waitFor(app.staticTexts["Aucun envoi"])
        capture("historique-vide", in: app)
        app.buttons["Questions"].tap()
        waitFor(app.staticTexts["Aucune question"])
    }

    func testReglagesEtLexique() {
        let app = launch("history")
        element("home.settings", in: app).tap()
        waitFor(element("settings.lexicon", in: app))
        XCTAssertTrue(app.staticTexts["Build installé"].exists || app.staticTexts["BUILD INSTALLÉ"].exists)
        capture("reglages", in: app)

        element("settings.lexicon", in: app).tap()
        waitFor(app.staticTexts["Acme"])
        XCTAssertTrue(app.staticTexts["ack me, ak me"].exists)
        capture("lexique", in: app)

        element("lexicon.add", in: app).tap()
        waitFor(app.navigationBars["Nouveau terme"])
        XCTAssertFalse(app.buttons["Enregistrer"].isEnabled)
        capture("lexique-nouveau-terme", in: app)
    }

    func testLexiqueVide() {
        let app = launch("demo")
        element("home.settings", in: app).tap()
        element("settings.lexicon", in: app).tap()
        waitFor(app.staticTexts["Aucun terme"])
        capture("lexique-vide", in: app)
    }

    func testAppairage() {
        let app = launch("unpaired")
        let paste = element("pairing.paste", in: app)
        waitFor(paste)
        XCTAssertTrue(app.staticTexts["Caméra indisponible : colle le code à la place"].exists)
        capture("appairage", in: app)
    }
}
