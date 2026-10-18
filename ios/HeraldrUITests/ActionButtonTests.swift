import XCTest

@MainActor
final class ActionButtonTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func testDictatesToHomeAtLaunchAndFromAnotherTarget() {
        let app = launch("demo")
        pressActionButton()
        waitForDictation(in: app)
        XCTAssertEqual(label(of: "compose.pill", in: app), "~ — main")
        capture("action-button-dictation", in: app)
        app.buttons["Cancel"].tap()

        element("tile.wS", in: app).tap()
        XCTAssertEqual(label(of: "target.workspace", in: app), "Acme")
        element("home.settings", in: app).tap()
        waitFor(app.navigationBars.firstMatch)
        pressActionButton()
        waitForDictation(in: app)
        XCTAssertEqual(label(of: "compose.pill", in: app), "~ — main")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(label(of: "target.workspace", in: app), "~")
    }

    func testKeepsTheOpenDraftAndItsTarget() {
        let app = launch("demo")
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

    func testUnpairedStaysOnPairing() {
        let app = launch("unpaired")
        waitFor(element("pairing.paste", in: app))
        pressActionButton()
        XCTAssertFalse(app.buttons["Stop dictation"].waitForExistence(timeout: 3))
        XCTAssertTrue(element("pairing.paste", in: app).exists)
    }

    private func pressActionButton() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.skelz0r.heraldr.debug.action-button" as CFString), nil, nil, true)
    }

    private func waitForDictation(in app: XCUIApplication) {
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow", "OK"])).firstMatch
        waitFor(app.buttons["Stop dictation"])
        for _ in 0..<2 where allow.waitForExistence(timeout: 2) {
            allow.tap()
        }
    }
}
