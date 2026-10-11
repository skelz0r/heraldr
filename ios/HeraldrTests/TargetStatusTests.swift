import Foundation
import Testing
@testable import Heraldr

@Suite("Pastille de la cible et des tuiles de workspace")
struct TargetStatusTests {
    @Test("l'agent cible travaille pendant qu'un autre tab du workspace a fini : la pastille est bleue, pas verte")
    func targetAgentWinsOverOtherTabs() throws {
        let workspaces = try JSONDecoder().decode([Workspace].self, from: Data("""
            [{"agent_status":"done","label":"Morris","number":2,"workspace_id":"w8"}]
            """.utf8))
        let agents = try JSONDecoder().decode([Agent].self, from: Data("""
            [
              {"agent":"claude","agent_status":"working","name":"morris-main","tab_id":"w8:t1","workspace_id":"w8"},
              {"agent":"claude","agent_status":"done","name":"morris-worktree","tab_id":"w8:t2","workspace_id":"w8"}
            ]
            """.utf8))
        let morris = try #require(workspaces.first)

        let state = AppModel.TargetState.resolve(for: morris, agents: agents, jobs: [], lastSentAt: nil, now: .now)

        #expect(state.dotStatus == .working)
    }
}
