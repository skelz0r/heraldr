import Foundation
import Testing

@testable import Heraldr

@Suite("Status dot of the target and of the workspace tiles")
struct TargetStatusTests {
    @Test("the target agent works while another tab of the workspace is done: the dot is blue, not green")
    func targetAgentWinsOverOtherTabs() throws {
        let workspaces = try JSONDecoder().decode(
            [Workspace].self,
            from: Data(
                """
                [{"agent_status":"done","label":"Morris","number":2,"workspace_id":"w8"}]
                """.utf8))
        let agents = try JSONDecoder().decode(
            [Agent].self,
            from: Data(
                """
                [
                  {"agent":"claude","agent_status":"working","name":"morris-main","tab_id":"w8:t1","workspace_id":"w8"},
                  {"agent":"claude","agent_status":"done","name":"morris-worktree","tab_id":"w8:t2","workspace_id":"w8"}
                ]
                """.utf8))
        let morris = try #require(workspaces.first)

        let state = AppModel.TargetState.resolve(for: morris, agents: agents, jobs: [], lastSentAt: nil, now: .now)

        #expect(state.dotStatus == .working)
    }

    private let acme = Workspace(id: "wB", number: 3, label: "acme")
    private let login2fa = Tab(id: "wB:tC", workspaceId: "wB", number: 4, label: "login-2fa")

    private func agents(_ json: String) throws -> [Agent] {
        try JSONDecoder().decode([Agent].self, from: Data(json.utf8))
    }

    @Test("a targeted tab follows its first Claude without a herdr name, neither a named agent nor another kind of agent")
    func tabFollowsItsFirstClaude() throws {
        let agents = try agents(
            """
            [
              {"agent":"claude","agent_status":"working","name":"acme-main","pane_id":"wB:p19","tab_id":"wB:t1","workspace_id":"wB"},
              {"agent":"codex","agent_status":"working","pane_id":"wB:pF","tab_id":"wB:tC","workspace_id":"wB"},
              {"agent":"claude","agent_status":"idle","name":"acme-review","pane_id":"wB:pE","tab_id":"wB:tC","workspace_id":"wB"},
              {"agent":"claude","agent_status":"blocked","pane_id":"wB:pG","tab_id":"wB:tC","workspace_id":"wB"},
              {"agent":"claude","agent_status":"idle","pane_id":"wB:pH","tab_id":"wB:tC","workspace_id":"wB"}
            ]
            """)

        let state = AppModel.TargetState.resolve(for: acme, tab: login2fa, agents: agents, jobs: [], lastSentAt: nil, now: .now)

        #expect(login2fa.firstClaude(in: agents)?.paneId == "wB:pG")
        #expect(state == .agent(.blocked, workingOnOurRequest: false))
    }

    @Test("a tab whose Claude is gone takes no more sends, and the app starts nothing in its place")
    func tabWithoutClaude() throws {
        let agents = try agents(
            """
            [{"agent":"claude","agent_status":"idle","name":"acme-main","pane_id":"wB:p19","tab_id":"wB:t1","workspace_id":"wB"}]
            """)

        let state = AppModel.TargetState.resolve(for: acme, tab: login2fa, agents: agents, jobs: [], lastSentAt: nil, now: .now)

        #expect(state == .tabWithoutClaude)
        #expect(!state.acceptsImmediately)
    }

    @Test("a send queued to a tab only keeps that tab busy, not the -main of the workspace")
    func tabJobStaysOnTheTab() throws {
        let agents = try agents(
            """
            [
              {"agent":"claude","agent_status":"idle","name":"acme-main","pane_id":"wB:p19","tab_id":"wB:t1","workspace_id":"wB"},
              {"agent":"claude","agent_status":"working","pane_id":"wB:pG","tab_id":"wB:tC","workspace_id":"wB"}
            ]
            """)
        let jobs = DispatchJob.parse(statusOutput: "20261012090000-1-ab\twB\twB:pG\tqueued\t\n")

        let tab = AppModel.TargetState.resolve(for: acme, tab: login2fa, agents: agents, jobs: jobs, lastSentAt: nil, now: .now)
        let main = AppModel.TargetState.resolve(for: acme, agents: agents, jobs: jobs, lastSentAt: nil, now: .now)

        #expect(tab == .sending)
        #expect(main == .agent(.idle, workingOnOurRequest: false))
    }

    private let heraldr = Workspace(id: "wH", number: 6, label: "📯 Heraldr")

    @Test("a renamed workspace keeps its -main, whatever its name, and the app does not offer to start another one")
    func renamedWorkspaceKeepsItsMain() throws {
        let agents = try agents(
            """
            [
              {"agent":"claude","agent_status":"working","name":"herdr-ios-companion-main","pane_id":"wH:p1","tab_id":"wH:t1","workspace_id":"wH"},
              {"agent":"claude","agent_status":"idle","pane_id":"wH:p7","tab_id":"wH:t2","workspace_id":"wH"}
            ]
            """)
        let jobs = DispatchJob.parse(statusOutput: "20261012090000-1-ab\twH\therdr-ios-companion-main\tqueued\t\n")

        #expect(
            AppModel.TargetState.resolve(for: heraldr, agents: agents, jobs: [], lastSentAt: nil, now: .now) == .agent(.working, workingOnOurRequest: false))
        #expect(AppModel.TargetState.resolve(for: heraldr, agents: agents, jobs: jobs, lastSentAt: nil, now: .now) == .sending)
    }

    @Test("the -main of another workspace never counts")
    func otherWorkspaceMainIgnored() throws {
        let agents = try agents(
            """
            [{"agent":"claude","agent_status":"idle","name":"heraldr-main","pane_id":"w9:p1","tab_id":"w9:t1","workspace_id":"w9"}]
            """)

        #expect(AppModel.TargetState.resolve(for: heraldr, agents: agents, jobs: [], lastSentAt: nil, now: .now) == .missing)
    }

    @Test("with several -main, the one named after the label is the target; without it, the send is blocked and names them, even with a queued send")
    func severalMains() throws {
        let agents = try agents(
            """
            [
              {"agent":"claude","agent_status":"working","name":"local_events-main","pane_id":"w8:p2","tab_id":"w8:t1","workspace_id":"w8"},
              {"agent":"claude","agent_status":"idle","name":"morris-main","pane_id":"w8:p1","tab_id":"w8:t1","workspace_id":"w8"}
            ]
            """)
        let morris = Workspace(id: "w8", number: 2, label: "🟡 Morris")
        let archives = Workspace(id: "w8", number: 2, label: "Archives")
        let pendingForMorris = DispatchJob.parse(statusOutput: "20261012090000-1-ab\tw8\tmorris-main\tqueued\t\n")

        let ambiguous = AppModel.TargetState.resolve(for: archives, agents: agents, jobs: [], lastSentAt: nil, now: .now)

        #expect(AppModel.TargetState.resolve(for: morris, agents: agents, jobs: [], lastSentAt: nil, now: .now) == .agent(.idle, workingOnOurRequest: false))
        #expect(ambiguous == .ambiguousMain(["local_events-main", "morris-main"]))
        #expect(!ambiguous.acceptsImmediately)
        #expect(AppModel.TargetState.resolve(for: archives, agents: agents, jobs: pendingForMorris, lastSentAt: nil, now: .now) == ambiguous)
    }
}
