import XCTest

@MainActor
final class HomeScreenTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCibleParDefautEtEtatDeChaqueAgent() {
        let app = launch("demo")
        waitFor(element("tile.wH", in: app))
        XCTAssertEqual(label(of: "target.workspace", in: app), "~")
        XCTAssertEqual(label(of: "target.tab", in: app), "main")
        XCTAssertEqual(label(of: "target.state", in: app), "Prêt")
        capture("accueil", in: app)

        let expected: [(tile: String, state: String, next: String)] = [
            ("wH", "Travaille", "Un nouvel envoi attendra la fin de son travail."),
            ("wS", "Envoi en cours…", "Un nouvel envoi partira juste après."),
            ("wM", "Prêt", "Un envoi vide son contexte puis transmet la demande."),
            ("wL", "État inconnu", "Un nouvel envoi attendra qu'il soit prêt."),
            ("wB", "Pas encore d'agent", "Un envoi lancera Claude dans le tab 1, nommé blog-main."),
        ]
        for (tile, state, next) in expected {
            element("tile.\(tile)", in: app).tap()
            XCTAssertEqual(label(of: "target.state", in: app), state, tile)
            XCTAssertEqual(label(of: "target.next", in: app), next, tile)
            capture("cible-\(tile)", in: app)
        }
    }

    func testAgentBloqueSansEnvoiEnFile() {
        let app = launch("demo")
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["journal-dictee"].firstMatch.tap()
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["tab 4"].firstMatch.tap()
        XCTAssertEqual(label(of: "target.tab", in: app), "tab 4")
        XCTAssertEqual(label(of: "target.state", in: app), "Te pose une question : réponds dans Claude mobile")
        XCTAssertEqual(label(of: "target.next", in: app), "Un nouvel envoi attendra que tu lui aies répondu.")
        capture("cible-tab-bloque", in: app)
    }

    func testCiblerUnTabParAppuiLong() {
        let app = launch("demo")
        let heraldr = element("tile.wH", in: app)
        waitFor(heraldr)
        heraldr.press(forDuration: 1)
        waitFor(app.buttons["harness-qa"])
        XCTAssertTrue(app.buttons["main"].exists)
        XCTAssertTrue(app.buttons["journal-dictee"].exists)
        capture("menu-tabs", in: app, dark: false)
        app.buttons["harness-qa"].tap()

        XCTAssertEqual(label(of: "target.workspace", in: app), "Heraldr")
        XCTAssertEqual(label(of: "target.tab", in: app), "harness-qa")
        XCTAssertEqual(label(of: "target.state", in: app), "Prêt")
        XCTAssertEqual(label(of: "target.next", in: app), "Un envoi transmet la demande telle quelle, sans vider son contexte.")
        capture("cible-tab", in: app)

        heraldr.tap()
        XCTAssertEqual(label(of: "target.tab", in: app), "main")
    }

    func testWorkspaceSansAutreTabClaude() {
        let app = launch("demo")
        let acme = element("tile.wS", in: app)
        waitFor(acme)
        acme.press(forDuration: 1)
        waitFor(app.descendants(matching: .any)["Aucun Claude dans les autres tabs"].firstMatch)
        capture("menu-sans-tab", in: app, dark: false)
    }

    func testMacInjoignable() {
        let app = launch("unreachable")
        waitFor(app.staticTexts["Mac injoignable"])
        waitFor(element("home.retry", in: app))
        capture("injoignable", in: app)
    }

    func testConnexionEnCours() {
        let app = launch("connecting")
        waitFor(app.staticTexts["Connexion au Mac…"])
        capture("connexion", in: app)
    }

    func testPresseVideAnnonce() {
        UIPasteboard.general.items = []
        let app = launch("demo")
        element("home.paste", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Presse-papier vide"))
        XCTAssertTrue(notice.label.contains("Copie d'abord le texte ou la capture à envoyer."))
        capture("presse-papier-vide", in: app)
    }
}
