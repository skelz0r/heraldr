import XCTest

@MainActor
final class NotificationTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func testTapOnAQuestionWithAppKilled() {
        let app = launchAllowingNotifications(environment: ["HERALDR_FAKE_MAC_KEPT_FOR_RELAUNCH": "1"])
        app.terminate()

        tapNotification()

        assertQuestionOpened(in: app, capturedAs: "unopened-question-app-killed")
    }

    func testTapOnAQuestionWithAppInBackground() {
        let app = launchAllowingNotifications()
        XCUIDevice.shared.press(.home)

        tapNotification()

        assertQuestionOpened(in: app, capturedAs: "unopened-question")
    }

    private func launchAllowingNotifications(environment: [String: String] = [:]) -> XCUIApplication {
        let app = launch("question", environment: environment)
        waitFor(element("tile.wS", in: app))
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    private func tapNotification() {
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Which database for the export")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "notification missing")
        banner.tap()
    }

    private func assertQuestionOpened(in app: XCUIApplication, capturedAs screen: String) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertEqual(label(of: "target.workspace", in: app), "Acme")
        let card = element("question.card", in: app)
        waitFor(card)
        XCTAssertTrue(app.staticTexts["acme-main is waiting for an answer"].exists)
        XCTAssertTrue(app.staticTexts["The session did not open in Claude."].exists)
        capture(screen, in: app)
    }
}
