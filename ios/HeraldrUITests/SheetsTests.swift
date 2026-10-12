import XCTest

@MainActor
final class SheetsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testHistoryTasksAndQuestions() {
        let app = launch("history")
        element("home.history", in: app).tap()
        waitFor(app.staticTexts["Add a dark mode to the settings screen and check the contrast of the status dots"])
        app.navigationBars["History"].swipeUp()
        XCTAssertTrue(app.staticTexts["2 screenshots attached"].exists)
        XCTAssertTrue(app.staticTexts["Heraldr — harness-qa"].exists)
        capture("history-tasks", in: app)
        app.collectionViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["agent acme-main belongs to workspace wM"].exists)
        XCTAssertTrue(app.staticTexts["1 screenshot attached"].exists)
        XCTAssertTrue(app.staticTexts["Send interrupted before the Mac replied."].exists)
        capture("history-failures", in: app)

        app.buttons["Questions"].tap()
        waitFor(app.staticTexts["The cache is cleared on every deploy."])
        capture("history-questions", in: app)
        app.staticTexts["How does the thumbnail cache work?"].tap()
        waitFor(app.staticTexts["The thumbnail cache lives in tmp/thumbnails."])
        capture("answer", in: app)
    }

    func testCopyThenResend() {
        let app = launch("history")
        element("home.history", in: app).tap()
        let copy = element("history.copy", in: app)
        waitFor(copy)
        copy.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 2))
        capture("history-copy", in: app, dark: false)

        element("history.resend", in: app).tap()
        let notice = element("notice", in: app)
        waitFor(notice)
        XCTAssertTrue(notice.label.contains("Heraldr"), notice.label)
    }

    func testEmptyHistory() {
        let app = launch("demo")
        element("home.history", in: app).tap()
        waitFor(app.staticTexts["No sends"])
        capture("empty-history", in: app)
        app.buttons["Questions"].tap()
        waitFor(app.staticTexts["No questions"])
    }

    func testSettingsAndLexicon() {
        let app = launch("history")
        element("home.settings", in: app).tap()
        waitFor(element("settings.lexicon", in: app))
        XCTAssertTrue(app.staticTexts["Installed build"].exists || app.staticTexts["INSTALLED BUILD"].exists)
        capture("settings", in: app)

        element("settings.lexicon", in: app).tap()
        waitFor(app.staticTexts["Acme"])
        XCTAssertTrue(app.staticTexts["ack me, acne"].exists)
        capture("lexicon", in: app)

        element("lexicon.add", in: app).tap()
        waitFor(app.navigationBars["New term"])
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        capture("lexicon-new-term", in: app)
    }

    func testEmptyLexicon() {
        let app = launch("demo")
        element("home.settings", in: app).tap()
        element("settings.lexicon", in: app).tap()
        waitFor(app.staticTexts["No terms"])
        capture("empty-lexicon", in: app)
    }

    func testPairing() {
        let app = launch("unpaired")
        let paste = element("pairing.paste", in: app)
        waitFor(paste)
        XCTAssertTrue(app.staticTexts["Camera unavailable: paste the code instead"].exists)
        capture("pairing", in: app)
    }
}
