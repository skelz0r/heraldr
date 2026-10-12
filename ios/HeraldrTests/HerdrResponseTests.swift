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
        let workspaces = try decode(
            [Workspace].self,
            """
            [
              {"active_tab_id":"wA:t1","agent_status":"done","focused":false,"label":"Home","number":1,"pane_count":4,"tab_count":2,"workspace_id":"wA"},
              {"active_tab_id":"wE:t1","agent_status":"working","focused":true,"label":"Video studio","number":5,"pane_count":2,"tab_count":1,"workspace_id":"wE"}
            ]
            """)

        #expect(
            workspaces == [
                Workspace(id: "wA", number: 1, label: "Home"),
                Workspace(id: "wE", number: 5, label: "Video studio"),
            ])
    }

    @Test("un état d'agent apparu dans une future version de herdr s'affiche inconnu sans casser la liste")
    func unknownAgentStatus() throws {
        let agents = try decode(
            [Agent].self,
            """
            [{"agent":"claude","agent_status":"compacting","name":"morris-main","tab_id":"w8:t1","workspace_id":"w8"}]
            """)

        #expect(agents.first?.agentStatus == .unknown)
    }

    @Test("un Claude lancé à la main, sans nom d'agent, ne casse pas la liste des agents")
    func unnamedAgent() throws {
        let agents = try decode(
            [Agent].self,
            """
            [
              {"agent":"claude","agent_session":{"value":"318c7ecb"},"agent_status":"idle","cwd":"/Users/me","pane_id":"wA:p1","tab_id":"wA:t1","workspace_id":"wA"},
              {"agent":"claude","agent_status":"done","name":"home-main","pane_id":"wA:p5","tab_id":"wA:t1","workspace_id":"wA"}
            ]
            """)

        #expect(agents.map(\.name) == [nil, "home-main"])
    }

    @Test("un agent sans tab_id ni workspace_id se lit, ses autres champs gardés")
    func agentWithoutTab() throws {
        let agents = try decode(
            [Agent].self,
            """
            [{"agent":"claude","agent_status":"idle","name":"orphelin-main","pane_id":"wA:p9"}]
            """)

        #expect(agents.first?.name == "orphelin-main")
        #expect(agents.first?.tabId == nil)
    }

    @Test("Home, le workspace numéro 1, passe en tête quel que soit son label, puis l'ordre herdr")
    func homeFirst() {
        let ordered = Workspace.ordered([
            Workspace(id: "w9", number: 3, label: "apistration"),
            Workspace(id: "w8", number: 2, label: "Morris"),
            Workspace(id: "wA", number: 1, label: "Home"),
        ])

        #expect(ordered.map(\.id) == ["wA", "w8", "w9"])
        #expect(ordered.first?.isHome == true)
    }

    @Test("la liste des tabs de herdr se lit ; le tab 1 s'affiche main quel que soit son label")
    func tabList() throws {
        let tabs = try decode(
            [Tab].self,
            """
            [
              {"tab_id":"wB:t1","workspace_id":"wB","number":1,"label":"1","focused":false,"pane_count":4,"agent_status":"idle"},
              {"tab_id":"wB:tC","workspace_id":"wB","number":4,"label":"login-2fa","focused":true,"pane_count":2,"agent_status":"working"},
              {"tab_id":"wB:tD","workspace_id":"wB","number":5,"label":"","pane_count":1}
            ]
            """)

        #expect(tabs.map(\.displayName) == ["main", "login-2fa", "tab 5"])
        #expect(Target(Workspace(id: "wB", number: 3, label: "acme"), tab: tabs[1]).label == "acme — login-2fa")
        #expect(Target(Workspace(id: "wB", number: 3, label: "acme")).label == "acme — main")
    }
}
