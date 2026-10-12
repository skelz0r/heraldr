import XCTest

@MainActor
final class SendFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testWriteAndSendToTheMain() {
        let app = launch("demo")
        element("tile.wM", in: app).tap()
        element("home.write", in: app).tap()
        let text = element("compose.text", in: app)
        waitFor(text)
        XCTAssertEqual(element("compose.target", in: app).label.hasPrefix("Naïve search — main"), true)
        XCTAssertEqual(label(of: "compose.state", in: app), "Ready. A send clears its context, then hands over the request.")
        XCTAssertFalse(element("compose.send", in: app).isEnabled)
        XCTAssertFalse(element("compose.clear", in: app).exists)
        capture("empty-preview", in: app)

        text.typeText("Add typo tolerance to the search")
        XCTAssertTrue(element("compose.send", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["Written"].exists)
        capture("written-preview", in: app)

        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Sent to Naïve search"))
        XCTAssertTrue(notice.label.contains("The Mac clears Claude's context, then hands it the request."))
        XCTAssertEqual(label(of: "target.state", in: app), "Working on your request")
        capture("sent-notice", in: app)
    }

    func testQueuedSendToABusyAgent() {
        let app = launch("demo")
        element("tile.wH", in: app).tap()
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("And add a test")
        XCTAssertEqual(label(of: "compose.state", in: app), "Working. A new send will wait until it finishes its work.")
        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Queued for Heraldr"))
        XCTAssertTrue(notice.label.contains("Claude is busy: the request goes out as soon as it is done."))
        capture("queued-notice", in: app)
    }

    func testSendToATabWithClear() {
        let app = launch("demo")
        element("tile.wH", in: app).press(forDuration: 1)
        app.buttons["harness-qa"].tap()
        element("home.write", in: app).tap()
        waitFor(element("compose.clear", in: app))
        XCTAssertEqual(label(of: "compose.state", in: app), "Ready. A send hands over the request as is, keeping its context.")
        element("compose.clear", in: app).tap()
        XCTAssertEqual(label(of: "compose.state", in: app), "Ready. A send clears its context, then hands over the request.")
        element("compose.text", in: app).typeText("Start over")
        capture("tab-clear-preview", in: app)

        element("compose.send", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Sent to Heraldr — harness-qa"))
        XCTAssertTrue(notice.label.contains("The Mac clears Claude's context, then hands it the request."))
    }

    func testChangeTargetInThePreview() {
        let app = launch("demo")
        waitFor(element("tile.wH", in: app))
        element("home.write", in: app).tap()
        element("compose.target", in: app).tap()
        waitFor(element("picker.wH:t2", in: app))
        capture("change-target", in: app)
        element("picker.wH:t2", in: app).tap()

        XCTAssertTrue(element("compose.target", in: app).label.hasPrefix("Heraldr — harness-qa"))
        XCTAssertTrue(element("compose.clear", in: app).exists)
    }

    func testFailureAnnouncedForAnAgentOfAnotherWorkspace() {
        let scenario = """
            {"workspaces":[{"id":"wA","number":1,"label":"~"},{"id":"wS","number":2,"label":"Acme"}],
             "agents":[{"name":"acme-main","kind":"claude","paneId":"wZ:p1","workspaceId":"wZ","tabId":"wZ:t1","status":"idle"}]}
            """
        let app = launch("custom", environment: ["HERALDR_FAKE_MAC": scenario])
        element("tile.wS", in: app).tap()
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("Wrong target")
        element("compose.send", in: app).tap()

        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Failed to send to Acme"), notice.label)
        XCTAssertTrue(notice.label.contains("agent acme-main belongs to workspace wZ"))
        capture("failure-notice", in: app)
    }

    func testRefusedSendStaysOnScreen() {
        let scenario = """
            {"workspaces":[{"id":"wA","number":1,"label":"~"}],
             "agents":[{"name":"home-main","kind":"claude","paneId":"wA:p1","workspaceId":"wA","tabId":"wA:t1","status":"idle"}],
             "failures":{"enqueue":"2:empty prompt"}}
            """
        let app = launch("custom", environment: ["HERALDR_FAKE_MAC": scenario])
        element("home.write", in: app).tap()
        element("compose.text", in: app).typeText("Request")
        element("compose.send", in: app).tap()

        XCTAssertEqual(label(of: "compose.error", in: app), "Command refused by the Mac (2): empty prompt")
        XCTAssertTrue(element("compose.text", in: app).exists)
        capture("failed-preview", in: app)
    }
}
