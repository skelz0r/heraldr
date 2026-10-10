import Foundation
import Testing
@testable import Heraldr

@Suite("Contrat des notifications entre l'app et le hook du Mac")
struct PushContractTests {
    @Test("l'appareil s'annonce dans le format que dispatch.sh register-push accepte")
    func registration() throws {
        let device = try #require(PushDevice(token: Data((0..<32).map { UInt8($0 * 7) })))

        #expect(device.token.wholeMatch(of: #/[0-9a-f]{64,200}/#) != nil)
        #expect(["sandbox", "production"].contains(device.environment))
        #expect(device.topic.wholeMatch(of: #/[A-Za-z0-9.-]+/#) != nil)
        #expect(device.teamId.wholeMatch(of: #/[A-Z0-9]{10}/#) != nil)
    }

    @Test("le tap sur une question envoyée par le hook cible le workspace de l'agent et ouvre sa session")
    func questionWithSession() throws {
        let question = try #require(QuestionNotification(userInfo: [
            "aps": ["alert": ["title": "Video studio", "subtitle": "video-studio-main", "body": "Quelle base ?"]],
            "workspace_id": "wE",
            "agent": "video-studio-main",
            "session_url": "https://claude.ai/code/session_01abc",
        ]))

        #expect(question.workspaceId == "wE")
        #expect(question.agent == "video-studio-main")
        #expect(question.sessionURL == URL(string: "https://claude.ai/code/session_01abc"))
    }

    @Test("sans lien de session, la question cible quand même son workspace")
    func questionWithoutSession() throws {
        let question = try #require(QuestionNotification(userInfo: ["workspace_id": "wE", "agent": "video-studio-main"]))

        #expect(question.workspaceId == "wE")
        #expect(question.sessionURL == nil)
    }
}
