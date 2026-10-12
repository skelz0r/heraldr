import XCTest

@MainActor
final class MacAndVoiceTests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
    }

    func testMenuDuMacPuisOublier() {
        let app = launch("demo")
        let mac = element("home.mac", in: app)
        waitFor(mac)
        XCTAssertTrue(mac.label.contains("moi@192.168.1.20"), mac.label)
        mac.tap()
        waitFor(app.buttons["Rafraîchir"])
        XCTAssertTrue(app.buttons["Oublier ce Mac"].exists)
        capture("menu-mac", in: app)

        app.buttons["Oublier ce Mac"].tap()
        waitFor(app.buttons["Oublier et réappairer"])
        XCTAssertTrue(app.staticTexts["La clé de cet iPhone restera autorisée sur le Mac tant que tu ne la retires pas de ~/.ssh/authorized_keys."].exists)
        capture("oublier-mac", in: app)
        app.buttons["Oublier et réappairer"].tap()

        waitFor(element("pairing.paste", in: app))
    }

    func testEcranDeDictee() {
        let app = launch("demo")
        element("home.voice", in: app).tap()
        let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Autoriser", "Allow", "OK"])).firstMatch
        for _ in 0..<2 where allow.waitForExistence(timeout: 3) {
            allow.tap()
        }
        waitFor(app.buttons["Arrêter la dictée"])
        XCTAssertTrue(app.buttons["Annuler"].exists)
        capture("dictee", in: app)

        app.buttons["Annuler"].tap()
        waitFor(element("home.voice", in: app))
    }
}
