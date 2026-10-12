import XCTest

@MainActor
final class NotificationTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func testTapSurUneQuestionAppTuee() {
        let app = launchAllowingNotifications()
        app.terminate()

        tapNotification()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        waitFor(element("pairing.paste", in: app))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(app.state, .runningForeground, "l'app relancée par le tap ne doit pas planter")
    }

    func testTapSurUneQuestionAppEnArrierePlan() {
        let app = launchAllowingNotifications()
        XCUIDevice.shared.press(.home)

        tapNotification()

        assertQuestionOpened(in: app)
    }

    private func launchAllowingNotifications() -> XCUIApplication {
        let app = launch("question")
        waitFor(element("tile.wS", in: app))
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    private func tapNotification() {
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Quelle base pour l'export")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "notification absente")
        banner.tap()
    }

    private func assertQuestionOpened(in app: XCUIApplication) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertEqual(label(of: "target.workspace", in: app), "Acme")
        let card = element("question.card", in: app)
        waitFor(card)
        XCTAssertTrue(app.staticTexts["acme-main attend une réponse"].exists)
        XCTAssertTrue(app.staticTexts["La session ne s'est pas ouverte dans Claude."].exists)
        capture("question-non-ouverte", in: app)
    }
}
