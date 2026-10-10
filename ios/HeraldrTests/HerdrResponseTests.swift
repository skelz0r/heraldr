import Foundation
import Testing
@testable import Heraldr

@Suite("Réponses de l'API herdr lues par l'app")
struct HerdrResponseTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("une liste de workspaces de herdr 0.9.3 se lit, champs inconnus ignorés")
    func workspaceList() throws {
        let workspaces = try decode([Workspace].self, """
            [
              {"active_tab_id":"wA:t1","agent_status":"done","focused":false,"label":"Home","number":1,"pane_count":4,"tab_count":2,"workspace_id":"wA"},
              {"active_tab_id":"wE:t1","agent_status":"working","focused":true,"label":"Video studio","number":5,"pane_count":2,"tab_count":1,"workspace_id":"wE"}
            ]
            """)

        #expect(workspaces == [
            Workspace(id: "wA", number: 1, label: "Home", agentStatus: .done),
            Workspace(id: "wE", number: 5, label: "Video studio", agentStatus: .working),
        ])
    }

    @Test("un état d'agent apparu dans une future version de herdr s'affiche inconnu sans casser la liste")
    func unknownAgentStatus() throws {
        let workspaces = try decode([Workspace].self, """
            [{"agent_status":"compacting","label":"Morris","number":2,"workspace_id":"w8"}]
            """)

        #expect(workspaces.first?.agentStatus == .unknown)
    }

    @Test("un Claude lancé à la main, sans nom d'agent, ne casse pas la liste des agents")
    func unnamedAgent() throws {
        let agents = try decode([Agent].self, """
            [
              {"agent":"claude","agent_session":{"value":"318c7ecb"},"agent_status":"idle","cwd":"/Users/me","pane_id":"wA:p1","tab_id":"wA:t1","workspace_id":"wA"},
              {"agent":"claude","agent_status":"done","name":"home-main","pane_id":"wA:p5","tab_id":"wA:t1","workspace_id":"wA"}
            ]
            """)

        #expect(agents.map(\.name) == [nil, "home-main"])
    }

    @Test("Home, le workspace numéro 1, passe en tête quel que soit son label, puis l'ordre herdr")
    func homeFirst() {
        let ordered = Workspace.ordered([
            Workspace(id: "w9", number: 3, label: "apistration", agentStatus: .idle),
            Workspace(id: "w8", number: 2, label: "Morris", agentStatus: .idle),
            Workspace(id: "wA", number: 1, label: "Home", agentStatus: .idle),
        ])

        #expect(ordered.map(\.id) == ["wA", "w8", "w9"])
        #expect(ordered.first?.isHome == true)
    }
}
