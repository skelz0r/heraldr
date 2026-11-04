import XCTest

@MainActor
final class DictationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDictateFromHomeAndTheActionButtonKeepingTheOpenDraft() {
        let app = launch("demo")
        pressActionButton()
        waitForDictation(in: app)
        XCTAssertEqual(label(of: "compose.pill", in: app), "~ — main")
        capture("action-button-dictation", in: app)
        app.buttons["Cancel"].tap()

        element("home.voice", in: app).tap()
        waitForDictation(in: app)
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
        waitFor(element("home.voice", in: app))

        element("tile.wS", in: app).tap()
        XCTAssertEqual(label(of: "target.workspace", in: app), "Acme")
        element("home.settings", in: app).tap()
        waitFor(app.navigationBars.firstMatch)
        pressActionButton()
        waitForDictation(in: app)
        XCTAssertEqual(label(of: "compose.pill", in: app), "~ — main")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(label(of: "target.workspace", in: app), "~")

        element("tile.wS", in: app).tap()
        element("home.write", in: app).tap()
        let text = element("compose.text", in: app)
        waitFor(text)
        text.typeText("Fix the invoices export.")
        pressActionButton()
        waitForDictation(in: app)
        XCTAssertEqual(label(of: "compose.pill", in: app), "Acme — main")
        app.buttons["Cancel"].tap()

        XCTAssertEqual(element("compose.text", in: app).value as? String, "Fix the invoices export.")
        XCTAssertTrue(element("compose.target", in: app).label.hasPrefix("Acme — main"))
    }

    private func waitForDictation(in app: XCUIApplication) {
        waitFor(app.buttons["Stop dictation"])
    }
}
