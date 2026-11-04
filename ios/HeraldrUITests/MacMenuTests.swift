import XCTest

@MainActor
final class MacMenuTests: XCTestCase {
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
}
