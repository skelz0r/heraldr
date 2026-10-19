import Foundation
import Testing
import UserNotifications

@testable import Heraldr

@Suite("Notification contract between the app and the Mac hook")
struct PushContractTests {
    private final class BundleMarker {}

    @Test("the device registers in the format dispatch.sh register-push accepts")
    func registration() throws {
        let device = try #require(PushDevice(token: Data((0..<32).map { UInt8($0 * 7) })))

        #expect(device.token.wholeMatch(of: #/[0-9a-f]{64,200}/#) != nil)
        #expect(["sandbox", "production"].contains(device.environment))
        #expect(device.topic.wholeMatch(of: #/[A-Za-z0-9.-]+/#) != nil)
        #expect(device.teamId.wholeMatch(of: #/[A-Z0-9]{10}/#) != nil)
    }

    @Test("a tap on a question sent by the hook targets the workspace of the agent and opens its session")
    func questionWithSession() throws {
        let question = try #require(
            QuestionNotification(userInfo: [
                "aps": ["alert": ["title": "Naïve search", "subtitle": "naive-search-main", "body": "Which database?"]],
                "workspace_id": "wE",
                "agent": "naive-search-main",
                "session_url": "https://claude.ai/code/session_01abc",
            ]))

        #expect(question.workspaceId == "wE")
        #expect(question.agent == "naive-search-main")
        #expect(question.sessionURL == URL(string: "https://claude.ai/code/session_01abc"))
    }

    @Test("without a session link, the question still targets its workspace")
    func questionWithoutSession() throws {
        let question = try #require(QuestionNotification(userInfo: ["workspace_id": "wE", "agent": "naive-search-main"]))

        #expect(question.workspaceId == "wE")
        #expect(question.sessionURL == nil)
    }

    @Test("a tap on an answer sent by dispatch.sh answer opens the answer of the send, not the Claude session")
    func answer() throws {
        let tap = try #require(
            NotificationTap(userInfo: [
                "aps": ["alert": ["title": "acme_app", "subtitle": "Answer", "body": "The cache is cleared on every deploy."]],
                "kind": "answer",
                "job_id": "20261012090000-41-ab12cd34",
                "workspace_id": "w1",
                "agent": "acme_app-main",
            ]))

        guard case .answer(let answer) = tap else {
            Issue.record("answer read as a question: \(tap)")
            return
        }
        #expect(answer.jobId == "20261012090000-41-ab12cd34")
        #expect(answer.workspaceId == "w1")
        #expect(answer.summary == "The cache is cleared on every deploy.")
    }

    @Test("a question notification stays a question")
    func questionTap() throws {
        let tap = try #require(NotificationTap(userInfo: ["workspace_id": "wE", "agent": "naive-search-main"]))

        #expect(tap == .question(try #require(QuestionNotification(userInfo: ["workspace_id": "wE", "agent": "naive-search-main"]))))
    }

    @Test(
        "a payload without workspace_id or agent is ignored on tap",
        arguments: [
            ["agent": "naive-search-main"], ["workspace_id": "wE"], ["kind": "answer", "workspace_id": "w1"],
        ])
    func incompletePayload(userInfo: [String: String]) {
        #expect(NotificationTap(userInfo: userInfo) == nil)
    }

    @Test("a question the hook offers to answer gives one action per option, each asking to unlock the iPhone")
    func answerableQuestion() throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "question-notification", withExtension: "json"))
        let userInfo = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let question = try #require(QuestionNotification(userInfo: userInfo))
        let reply = try #require(question.reply)

        #expect(reply.paneId == "w1:p2")
        #expect(reply.questionId.wholeMatch(of: #/[0-9a-f]{16}/#) != nil)
        #expect(reply.category.identifier == "question.\(reply.questionId)")
        #expect(reply.category.actions.map(\.title) == ["Postgres", "SQLite"])
        #expect(reply.category.actions.allSatisfy { $0.options.contains(.authenticationRequired) })
        let chosen = try #require(reply.category.actions.last)
        #expect(reply.option(forAction: chosen.identifier) == QuestionReply.Option(number: 2, label: "SQLite"))
    }

    @Test(
        "a question without readable options can only be opened, never answered from the notification",
        arguments: [
            #"{}"#,
            #"{"options": []}"#,
            #"{"options": [{"number": 1}]}"#,
            #"{"options": [{"number": 1, "label": "Postgres"}, {"label": "SQLite"}]}"#,
            #"{"options": [{"number": 1, "label": "A"}, {"number": 2, "label": "B"}, {"number": 3, "label": "C"}, {"number": 4, "label": "D"}, {"number": 5, "label": "E"}]}"#,
            #"{"options": [{"number": 12, "label": "Postgres"}]}"#,
        ])
    func unanswerableQuestion(options: String) throws {
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(options.utf8)) as? [String: Any])
        let userInfo: [String: Any] = ["workspace_id": "w1", "agent": "acme_app-main", "pane_id": "w1:p2", "question_id": "685f9aaf7c411d69"]
        let question = try #require(QuestionNotification(userInfo: userInfo.merging(parsed) { $1 }))

        #expect(question.reply == nil)
    }

    @Test("the latest questions keep their answer buttons, however many came before")
    func latestCategoriesKept() async throws {
        let replies = try (0..<40).map { index in
            try #require(
                QuestionReply(userInfo: [
                    "pane_id": "w1:p2", "question_id": String(format: "%016x", 0xc0ff_ee00 + index),
                    "options": [["number": 1, "label": "Postgres"], ["number": 2, "label": "SQLite"]],
                ]))
        }

        for reply in replies {
            await reply.register()
        }

        let registered = Set(await UNUserNotificationCenter.current().notificationCategories().map(\.identifier))
        #expect(Set(replies.suffix(8).map(\.categoryIdentifier)).isSubset(of: registered))
    }
}
