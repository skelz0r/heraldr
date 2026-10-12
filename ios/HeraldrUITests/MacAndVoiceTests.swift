import XCTest

@MainActor
final class MacAndVoiceTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func testMacMenuThenForget() {
        let app = launch("demo")
        let mac = element("home.mac", in: app)
        waitFor(mac)
        XCTAssertTrue(mac.label.contains("me@192.168.1.20"), mac.label)
        mac.tap()
        waitFor(app.buttons["Refresh"])
        XCTAssertTrue(app.buttons["Forget this Mac"].exists)
        capture("mac-menu", in: app)

        app.buttons["Forget this Mac"].tap()
        waitFor(app.buttons["Forget and pair again"])
        XCTAssertTrue(app.staticTexts["This iPhone's key stays authorized on the Mac until you remove it from ~/.ssh/authorized_keys."].exists)
        capture("forget-mac", in: app)
        app.buttons["Forget and pair again"].tap()

        waitFor(element("pairing.paste", in: app))
    }

    func testDictationScreen() {
        let app = launch("demo")
        element("home.voice", in: app).tap()
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow", "OK"])).firstMatch
        for _ in 0..<2 where allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        waitFor(app.buttons["Stop dictation"])
        XCTAssertTrue(app.buttons["Cancel"].exists)
        capture("dictation", in: app)

        app.buttons["Cancel"].tap()
        waitFor(element("home.voice", in: app))
    }
}
