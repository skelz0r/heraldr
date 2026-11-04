import XCTest

@MainActor
final class HomeScreenTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testDefaultTargetAndStateOfEachAgent() {
        let app = launch("demo")
        waitFor(element("tile.wH", in: app))
        XCTAssertEqual(label(of: "target.workspace", in: app), "~")
        XCTAssertEqual(label(of: "target.tab", in: app), "main")
        XCTAssertEqual(label(of: "target.state", in: app), "Ready")
        capture("home", in: app)

        let expected: [(tile: String, state: String, next: String)] = [
            ("wH", "Working", "A new send will wait until it finishes its work."),
            ("wS", "Sending…", "A new send will go out right after."),
            ("wM", "Ready", "A send clears its context, then hands over the request."),
            ("wL", "Unknown state", "A new send will wait until it is ready."),
            ("wB", "No agent yet", "A send will start Claude in tab 1, named blog-main."),
            ("wK", "Several -main Claudes", "A send will fail: keep only one of w---morris-main, morris_api-main, or name it morris-main."),
        ]
        for (tile, state, next) in expected {
            element("tile.\(tile)", in: app).tap()
            XCTAssertEqual(label(of: "target.state", in: app), state, tile)
            XCTAssertEqual(label(of: "target.next", in: app), next, tile)
            capture("target-\(tile)", in: app)
        }
    }

    func testBlockedAgentWithoutQueuedSend() {
        let app = launch("demo")
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["dictation-journal"].firstMatch.tap()
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["tab 4"].firstMatch.tap()
        XCTAssertEqual(label(of: "target.tab", in: app), "tab 4")
        XCTAssertEqual(label(of: "target.state", in: app), "Asking you a question: answer in Claude mobile")
        XCTAssertEqual(label(of: "target.next", in: app), "A new send will wait until you have answered it.")
        capture("target-blocked-tab", in: app)
    }

    func testTargetATabWithLongPress() {
        let app = launch("demo")
        let heraldr = element("tile.wH", in: app)
        waitFor(heraldr)
        heraldr.press(forDuration: 1)
        waitFor(app.buttons["harness-qa"])
        XCTAssertTrue(app.buttons["main"].exists)
        XCTAssertTrue(app.buttons["dictation-journal"].exists)
        capture("tabs-menu", in: app, dark: false)
        app.buttons["harness-qa"].tap()

        XCTAssertEqual(label(of: "target.workspace", in: app), "Heraldr")
        XCTAssertEqual(label(of: "target.tab", in: app), "harness-qa")
        XCTAssertEqual(label(of: "target.state", in: app), "Ready")
        XCTAssertEqual(label(of: "target.next", in: app), "A send hands over the request as is, keeping its context.")
        capture("target-tab", in: app)

        heraldr.tap()
        XCTAssertEqual(label(of: "target.tab", in: app), "main")
    }

    func testWorkspaceWithoutOtherClaudeTab() {
        let app = launch("demo")
        let acme = element("tile.wS", in: app)
        waitFor(acme)
        acme.press(forDuration: 1)
        waitFor(app.descendants(matching: .any)["No Claude in the other tabs"].firstMatch)
        capture("menu-without-tab", in: app, dark: false)
    }

    func testStartClaudeFromLongPressWithoutMain() {
        let app = launch("demo")
        let blog = element("tile.wB", in: app)
        waitFor(blog)
        blog.press(forDuration: 1)
        let start = element("tile.wB.start", in: app)
        waitFor(start)
        capture("menu-start-claude", in: app)
        start.tap()

        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Starting Claude in Blog"))
        XCTAssertTrue(notice.label.contains("The Mac starts Claude in tab 1, named blog-main."))
        capture("started-claude", in: app)

        blog.press(forDuration: 1)
        waitFor(app.descendants(matching: .any)["No Claude in the other tabs"].firstMatch)
        XCTAssertFalse(element("tile.wB.start", in: app).exists)
    }

    func testNoStartClaudeWhenTheWorkspaceHasItsMain() {
        let app = launch("demo")
        let heraldr = element("tile.wH", in: app)
        waitFor(heraldr)
        heraldr.press(forDuration: 1)
        waitFor(app.buttons["harness-qa"])
        XCTAssertFalse(element("tile.wH.start", in: app).exists)
        app.buttons["harness-qa"].tap()

        let morris = element("tile.wK", in: app)
        morris.press(forDuration: 1)
        waitFor(app.descendants(matching: .any)["No Claude in the other tabs"].firstMatch)
        XCTAssertFalse(element("tile.wK.start", in: app).exists)
    }

    func testMacUnreachable() {
        let app = launch("unreachable")
        waitFor(app.staticTexts["Mac unreachable"])
        waitFor(element("home.retry", in: app))
        capture("unreachable", in: app)
    }

    func testConnecting() {
        let app = launch("connecting")
        waitFor(app.staticTexts["Connecting to the Mac…"])
        capture("connecting", in: app)
    }

    func testEmptyClipboardAnnounced() {
        UIPasteboard.general.items = []
        let app = launch("demo")
        element("home.paste", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Clipboard empty"))
        XCTAssertTrue(notice.label.contains("First copy the text or screenshot to send."))
        capture("empty-clipboard", in: app)
    }
}
