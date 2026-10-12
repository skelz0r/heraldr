import XCTest

@MainActor
final class SendFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testEcrireEtEnvoyerAuMain() {
        let app = launch("demo")
        element("tile.wM", in: app).tap()
        element("home.write", in: app).tap()
        let text = element("compose.text", in: app)
        waitFor(text)
        XCTAssertEqual(element("compose.target", in: app).label.hasPrefix("Vidéo studio — main"), true)
        XCTAssertEqual(label(of: "compose.state", in: app), "Prêt. Un envoi vide son contexte puis transmet la demande.")
        XCTAssertFalse(element("compose.send", in: app).isEnabled)
        XCTAssertFalse(element("compose.clear", in: app).exists)
        capture("apercu-vide", in: app)

        text.typeText("Ajoute un sous-titre aux vidéos")
        XCTAssertTrue(element("compose.send", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["Écrit"].exists)
        capture("apercu-ecrit", in: app)

        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Envoyé à Vidéo studio"))
        XCTAssertTrue(notice.label.contains("Le Mac vide le contexte de Claude, puis lui transmet la demande."))
        XCTAssertEqual(label(of: "target.state", in: app), "Travaille sur ta demande")
        capture("notice-envoye", in: app)
    }

    func testEnvoiEnFileVersUnAgentOccupe() {
        let app = launch("demo")
        element("tile.wH", in: app).tap()
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("Et ajoute un test")
        XCTAssertEqual(label(of: "compose.state", in: app), "Travaille. Un nouvel envoi attendra la fin de son travail.")
        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("En file pour Heraldr"))
        XCTAssertTrue(notice.label.contains("Claude est occupé : la demande partira dès qu'il aura fini."))
        capture("notice-en-file", in: app)
    }

    func testEnvoiVersUnTabAvecClear() {
        let app = launch("demo")
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["harness-qa"].tap()
        element("home.write", in: app).tap()
        waitFor(element("compose.clear", in: app))
        XCTAssertEqual(label(of: "compose.state", in: app), "Prêt. Un envoi transmet la demande telle quelle, sans vider son contexte.")
        element("compose.clear", in: app).tap()
        XCTAssertEqual(label(of: "compose.state", in: app), "Prêt. Un envoi vide son contexte puis transmet la demande.")
        element("compose.text", in: app).typeText("Repars de zéro")
        capture("apercu-tab-clear", in: app)

        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Envoyé à Heraldr — harness-qa"))
        XCTAssertTrue(notice.label.contains("Le Mac vide le contexte de Claude, puis lui transmet la demande."))
    }

    func testChangerDeCibleDansLApercu() {
        let app = launch("demo")
        waitFor(element("tile.wH", in: app))
        element("home.write", in: app).tap()
        element("compose.target", in: app).tap()
        waitFor(element("picker.wH:t2", in: app))
        capture("changer-de-cible", in: app)
        element("picker.wH:t2", in: app).tap()

        XCTAssertTrue(element("compose.target", in: app).label.hasPrefix("Heraldr — harness-qa"))
        XCTAssertTrue(element("compose.clear", in: app).exists)
    }

    func testEchecAnnonceVersUnAgentDUnAutreWorkspace() {
        let scenario = """
            {"workspaces":[{"id":"wA","number":1,"label":"~"},{"id":"wS","number":2,"label":"Acme"}],
             "agents":[{"name":"acme-main","kind":"claude","paneId":"wZ:p1","workspaceId":"wZ","tabId":"wZ:t1","status":"idle"}]}
            """
        let app = launch("custom", environment: ["HERALDR_FAKE_MAC": scenario])
        element("tile.wS", in: app).tap()
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("Mauvaise cible")
        element("compose.send", in: app).tap()

        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Échec de l'envoi vers Acme"), notice.label)
        XCTAssertTrue(notice.label.contains("l'agent acme-main appartient au workspace wZ"))
        capture("notice-echec", in: app)
    }

    func testEnvoiRefuseRestaffiche() {
        let scenario = """
            {"workspaces":[{"id":"wA","number":1,"label":"~"}],
             "agents":[{"name":"home-main","kind":"claude","paneId":"wA:p1","workspaceId":"wA","tabId":"wA:t1","status":"idle"}],
             "failures":{"enqueue":"empty prompt"}}
            """
        let app = launch("custom", environment: ["HERALDR_FAKE_MAC": scenario])
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("Demande")
        element("compose.send", in: app).tap()

        XCTAssertEqual(label(of: "compose.error", in: app), "Commande refusée par le Mac (1) : empty prompt")
        XCTAssertTrue(element("compose.text", in: app).exists)
        capture("apercu-echec", in: app)
    }
}
