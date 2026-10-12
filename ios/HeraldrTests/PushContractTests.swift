import Foundation
import Testing

@testable import Heraldr

@Suite("Notification contract between the app and the Mac hook")
struct PushContractTests {
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
}
