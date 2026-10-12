import Foundation
import Testing

@testable import Heraldr

@Suite("herdr API responses read by the app")
struct HerdrResponseTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("a herdr 0.9.3 workspace list is read, unknown fields ignored")
    func workspaceList() throws {
        let workspaces = try decode(
            [Workspace].self,
            """
            [
              {"active_tab_id":"wA:t1","agent_status":"done","focused":false,"label":"Home","number":1,"pane_count":4,"tab_count":2,"workspace_id":"wA"},
              {"active_tab_id":"wE:t1","agent_status":"working","focused":true,"label":"Naïve search","number":5,"pane_count":2,"tab_count":1,"workspace_id":"wE"}
            ]
            """)

        #expect(
            workspaces == [
                Workspace(id: "wA", number: 1, label: "Home"),
                Workspace(id: "wE", number: 5, label: "Naïve search"),
            ])
    }

    @Test("an agent state introduced by a future herdr version shows as unknown without breaking the list")
    func unknownAgentStatus() throws {
        let agents = try decode(
            [Agent].self,
            """
            [{"agent":"claude","agent_status":"compacting","name":"morris-main","tab_id":"w8:t1","workspace_id":"w8"}]
            """)

        #expect(agents.first?.agentStatus == .unknown)
    }

    @Test("a Claude started by hand, without agent name, does not break the agent list")
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

    @Test("an agent without tab_id or workspace_id is read, its other fields kept")
    func agentWithoutTab() throws {
        let agents = try decode(
            [Agent].self,
            """
            [{"agent":"claude","agent_status":"idle","name":"orphan-main","pane_id":"wA:p9"}]
            """)

        #expect(agents.first?.name == "orphan-main")
        #expect(agents.first?.tabId == nil)
    }

    @Test("Home, workspace number 1, comes first whatever its label, then the herdr order")
    func homeFirst() {
        let ordered = Workspace.ordered([
            Workspace(id: "w9", number: 3, label: "apistration"),
            Workspace(id: "w8", number: 2, label: "Morris"),
            Workspace(id: "wA", number: 1, label: "Home"),
        ])

        #expect(ordered.map(\.id) == ["wA", "w8", "w9"])
        #expect(ordered.first?.isHome == true)
    }

    @Test("the herdr tab list is read; tab 1 shows as main whatever its label")
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
