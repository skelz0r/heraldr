import XCTest

@MainActor
extension XCTestCase {
    func launch(_ preset: String, environment: [String: String] = [:]) -> XCUIApplication {
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-HeraldrFakeMac", preset]
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    func capture(_ name: String, in app: XCUIApplication, dark: Bool = true) {
        settle()
        attach(app.screenshot(), named: "\(name)-light")
        guard dark else { return }
        XCUIDevice.shared.appearance = .dark
        settle()
        attach(app.screenshot(), named: "\(name)-dark")
        XCUIDevice.shared.appearance = .light
        settle()
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) missing", file: file, line: line)
    }

    func label(of identifier: String, in app: XCUIApplication) -> String {
        let found = element(identifier, in: app)
        waitFor(found)
        let text = app.staticTexts.matching(identifier: identifier).firstMatch
        return text.exists ? text.label : found.label
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }
}
