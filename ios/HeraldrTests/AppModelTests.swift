import Foundation
import Testing

@testable import Heraldr

@MainActor
private struct Session {
    let mac: FakeMac
    let model: AppModel
    let suite: String

    init(_ scenario: FakeMacScenario, suite: String = "heraldr-tests-\(UUID().uuidString)") async {
        mac = FakeMac(scenario)
        model = AppModel(environment: .fake(scenario, mac: mac, suiteName: suite))
        self.suite = suite
        await model.refresh()
    }

    func relaunched() async -> AppModel {
        let model = AppModel(environment: .fake(await mac.scenario, mac: mac, suiteName: suite, relaunching: true))
        await model.refresh()
        return model
    }

    func workspace(_ id: String) throws -> Workspace {
        try #require(model.workspaces.first { $0.id == id })
    }

    func tab(_ id: String) throws -> Tab {
        try #require(model.tabs.first { $0.id == id })
    }
}

private func world(
    agents: [FakeMacScenario.Agent] = [], jobs: [FakeMacScenario.Job] = [], failures: [String: String] = [:]
) -> FakeMacScenario {
    FakeMacScenario(
        workspaces: [
            .init(id: "wA", number: 1, label: "~"),
            .init(id: "wS", number: 2, label: "Acme"),
            .init(id: "wM", number: 3, label: "Naïve search"),
        ],
        tabs: [
            .init(id: "wA:t1", workspaceId: "wA", number: 1, label: "claude"),
            .init(id: "wS:t1", workspaceId: "wS", number: 1, label: "claude"),
            .init(id: "wS:t2", workspaceId: "wS", number: 2, label: "login-2fa"),
        ],
        agents: agents, jobs: jobs, failures: failures)
}

private func main(_ name: String, in workspace: String, _ status: String) -> FakeMacScenario.Agent {
    .init(name: name, kind: "claude", paneId: "\(workspace):p1", workspaceId: workspace, tabId: "\(workspace):t1", status: status)
}

private func tabClaude(_ status: String) -> FakeMacScenario.Agent {
    .init(name: nil, kind: "claude", paneId: "wS:p9", workspaceId: "wS", tabId: "wS:t2", status: status)
}

@MainActor
@Suite("Notice shown after a send")
struct SendNoticeTests {
    @Test("to a ready main: the Mac clears the context then hands over")
    func readyMain() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))

        try await session.model.send("Fix the bug", to: Target(session.workspace("wS")))

        #expect(session.model.notice?.kind == .sent)
        #expect(session.model.notice?.title == "Sent to Acme")
        #expect(session.model.notice?.detail == "The Mac clears Claude's context, then hands it the request.")
    }

    @Test("without agent: the Mac starts Claude in tab 1 under the agent name")
    func missingAgent() async throws {
        let session = await Session(world())

        try await session.model.send("Add a subtitle", to: Target(session.workspace("wM")))

        #expect(session.model.notice?.title == "Sent to Naïve search")
        #expect(session.model.notice?.detail == "The Mac starts Claude in tab 1, named naive-search-main, then hands it the request.")
    }

    @Test("to a renamed workspace: the existing -main gets the request, no other one is started")
    func renamedWorkspace() async throws {
        let session = await Session(world(agents: [main("herdr-ios-companion-main", in: "wM", "idle")]))

        try await session.model.send("Add a subtitle", to: Target(session.workspace("wM")))

        #expect(session.model.notice?.detail == "The Mac clears Claude's context, then hands it the request.")
        #expect(await session.mac.scenario.jobs?.map(\.agent) == ["herdr-ios-companion-main"])
    }

    @Test("to an agent that works, is blocked or already has a queued send: queued")
    func busyAgent() async throws {
        let session = await Session(
            world(
                agents: [main("acme-main", in: "wS", "blocked"), main("home-main", in: "wA", "idle")],
                jobs: [.init(id: "j1", workspaceId: "wA", agent: "home-main", state: "queued")]))

        try await session.model.send("After your question", to: Target(session.workspace("wS")))
        #expect(session.model.notice?.kind == .queued)
        #expect(session.model.notice?.title == "Queued for Acme")
        #expect(session.model.notice?.detail == "Claude is busy: the request goes out as soon as it is done.")

        try await session.model.send("After the pending send", to: Target(session.workspace("wA")))
        #expect(session.model.notice?.title == "Queued for ~")
    }

    @Test("to a ready tab: as is without /clear, context cleared with /clear")
    func readyTab() async throws {
        let session = await Session(world(agents: [tabClaude("done")]))
        let target = Target(try session.workspace("wS"), tab: try session.tab("wS:t2"))

        try await session.model.send("Make the button bigger", to: target)
        #expect(session.model.notice?.title == "Sent to Acme — login-2fa")
        #expect(session.model.notice?.detail == "The Mac hands the request as is to Claude, which keeps its context.")

        await session.mac.update { $0.agents?[0].status = "idle" }
        await session.model.refresh()
        try await session.model.send("Start over", to: target, clearingContext: true)
        #expect(session.model.notice?.detail == "The Mac clears Claude's context, then hands it the request.")
        #expect(
            await session.mac.commands.filter { $0.hasPrefix("enqueue-pane") } == [
                "enqueue-pane wS wS:p9 keep", "enqueue-pane wS wS:p9 clear",
            ])
    }
}

@MainActor
@Suite("Failed send")
struct SendFailureTests {
    @Test("a send refused by the Mac reports its error to the preview and is marked failed in the history")
    func refusedByMac() async throws {
        let session = await Session(world(failures: ["enqueue": "2:invalid agent name: x"]))

        await #expect(throws: MacLinkError.self) {
            try await session.model.send("Request", to: Target(try session.workspace("wS")))
        }

        let entry = try #require(session.model.history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.error == "Command refused by the Mac (2): invalid agent name: x")
    }

    @Test("several -main, none named after the label: the target says so and the Mac refuses the send")
    func severalMains() async throws {
        let session = await Session(
            world(agents: [main("w---acme-main", in: "wS", "idle"), main("acme_api-main", in: "wS", "idle")]))
        let target = Target(try session.workspace("wS"))

        #expect(session.model.targetState(for: target) == .ambiguousMain(["w---acme-main", "acme_api-main"]))
        await #expect(throws: MacLinkError.self) { try await session.model.send("Request", to: target) }

        #expect(
            session.model.history.entries.first?.error
                == "Command refused by the Mac (2): several -main agents in wS: w---acme-main acme_api-main")
        #expect(await session.mac.scenario.jobs?.isEmpty ?? true)
    }

    @Test("a send that fails on the Mac before the next refresh is announced")
    func failsBeforeNextRefresh() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wM", "idle")]))

        try await session.model.send("Wrong target", to: Target(session.workspace("wS")))

        #expect(session.model.notice?.kind == .failed)
        #expect(session.model.notice?.title == "Failed to send to Acme")
        #expect(session.model.notice?.detail == "agent acme-main belongs to workspace wM")
    }

    @Test("a send seen failed by another refresh before the Mac returned its id is still announced")
    func failureSeenBeforeJobId() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wM", "idle")]))
        await session.mac.hold("enqueue:done")
        let acme = try session.workspace("wS")
        let sending = Task { try await session.model.send("Wrong target", to: Target(acme)) }
        while !(await session.mac.isWaiting(at: "enqueue:done")) { await Task.yield() }
        await session.model.refresh()
        await session.mac.release("enqueue:done")

        try await sending.value

        #expect(session.model.notice?.title == "Failed to send to Acme")
        #expect(session.model.notice?.detail == "agent acme-main belongs to workspace wM")
    }

    @Test("two tracked sends that fail between two refreshes are both announced")
    func twoFailures() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "working"), main("home-main", in: "wA", "working")]))
        try await session.model.send("First", to: Target(session.workspace("wS")))
        try await session.model.send("Second", to: Target(session.workspace("wA")))
        let jobs = await session.mac.scenario.jobs ?? []

        for job in jobs {
            await session.mac.setJob(job.id, state: "failed", error: "agent wait: agent_not_found")
        }
        await session.model.refresh()

        #expect(session.model.notice?.title == "2 sends failed")
        #expect(session.model.notice?.detail == "Acme: agent wait: agent_not_found\n~: agent wait: agent_not_found")
    }

    @Test("a failure already announced is not announced again at the next refresh")
    func announcedOnce() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wM", "idle")]))
        try await session.model.send("Wrong target", to: Target(session.workspace("wS")))
        #expect(session.model.notice?.kind == .failed)
        session.model.notice = nil

        await session.model.refresh()

        #expect(session.model.notice == nil)
    }
}

@MainActor
@Suite("Screenshots attached to a send")
struct SendImagesTests {
    @Test("screenshots are stored on the Mac one by one, then cited by their path in the request")
    func imagesUploadedThenCited() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))

        try await session.model.send("The button overflows", images: [Data([1]), Data([2])], to: Target(session.workspace("wS")))

        let commands = await session.mac.commands.filter { $0.hasPrefix("attach") || $0.hasPrefix("enqueue") }
        #expect(commands == ["attach jpg", "attach jpg", "enqueue wS QWNtZQ=="])
        let prompt = try #require(await session.mac.prompts.first)
        #expect(
            prompt.contains(
                "The button overflows\n\nAttached screenshots, read them with Read:\n- /Users/me/.local/state/heraldr/attachments/capture-101.jpg\n- /Users/me/.local/state/heraldr/attachments/capture-102.jpg"
            ))
        #expect(session.model.history.entries.first?.attachments?.count == 2)
    }

    @Test("a refused screenshot fails the send before the job, the stored screenshots stay in the history")
    func refusedImage() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))
        await session.mac.hold("attach")
        let sending = Task { try await session.model.send("Two screenshots", images: [Data([1]), Data([2])], to: Target(session.workspace("wS"))) }
        while !(await session.mac.isWaiting(at: "attach")) { await Task.yield() }
        await session.mac.release("attach", keepHolding: true)
        while !(await session.mac.isWaiting(at: "attach")) { await Task.yield() }
        await session.mac.update { $0.failures = ["attach": "1:attachments dir unavailable"] }
        await session.mac.release("attach")

        await #expect(throws: MacLinkError.self) { try await sending.value }

        let entry = try #require(session.model.history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.attachments == ["/Users/me/.local/state/heraldr/attachments/capture-101.jpg"])
        #expect(await session.mac.prompts.isEmpty)
    }
}

@MainActor
@Suite("Screen refresh")
struct RefreshTests {
    @Test("a tab.list failure keeps the last tab list, the rest of the screen is updated")
    func tabListFailureKeepsTabs() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))
        await session.mac.update {
            $0.failures = ["tab.list": "tab.list unavailable"]
            $0.agents?[0].status = "working"
        }

        await session.model.refresh()

        #expect(session.model.connection == .online)
        #expect(session.model.tabs.map(\.id) == ["wA:t1", "wS:t1", "wS:t2"])
        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.working, workingOnOurRequest: false))
    }

    @Test("without a tab list received, a tab.list failure lets the workspaces show without tabs")
    func tabListFailureFirstTime() async throws {
        let session = await Session(world(failures: ["tab.list": "tab.list unavailable"]))

        #expect(session.model.connection == .online)
        #expect(session.model.workspaces.count == 3)
        #expect(session.model.tabs.isEmpty)
    }

    @Test("a refresh requested during another one is not lost")
    func refreshDuringRefresh() async throws {
        let session = await Session(world())
        await session.mac.hold("status")
        let first = Task { await session.model.refresh() }
        while !(await session.mac.isWaiting(at: "status")) { await Task.yield() }
        await session.mac.update { $0.workspaces?.append(.init(id: "wN", number: 4, label: "New")) }
        await session.model.refresh()
        await session.mac.release("status")

        await first.value

        #expect(session.model.workspaces.map(\.id).contains("wN"))
    }

    @Test("an agent without tab_id or workspace_id does not prevent reading the others")
    func agentWithoutTab() async throws {
        let session = await Session(
            world(agents: [
                .init(name: "orphan-main", kind: "claude", paneId: nil, workspaceId: nil, tabId: nil, status: "idle"),
                main("acme-main", in: "wS", "blocked"),
            ]))

        #expect(session.model.connection == .online)
        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.blocked, workingOnOurRequest: false))
    }

    @Test("a targeted tab that disappears from herdr hands the target back to the main of its workspace")
    func targetedTabDisappears() async throws {
        let session = await Session(world(agents: [tabClaude("idle")]))
        session.model.select(try session.workspace("wS"), tab: try session.tab("wS:t2"))
        #expect(session.model.selectedTarget?.tab?.id == "wS:t2")

        await session.mac.update {
            $0.tabs?.removeAll { $0.id == "wS:t2" }
            $0.agents = []
        }
        await session.model.refresh()

        #expect(session.model.selectedTarget?.workspace.id == "wS")
        #expect(session.model.selectedTarget?.tab == nil)
    }
}

@MainActor
@Suite("Target working on the app's request")
struct WorkingOnOurRequestTests {
    @Test("after a send, the target works on your request, even after the app relaunches")
    func survivesRelaunch() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))
        try await session.model.send("Fix the bug", to: Target(session.workspace("wS")))
        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.working, workingOnOurRequest: true))

        let relaunched = await session.relaunched()
        let acme = try #require(relaunched.workspaces.first { $0.id == "wS" })

        #expect(relaunched.targetState(for: acme) == .agent(.working, workingOnOurRequest: true))
    }

    @Test("a failed send does not count as a pending request")
    func failedSendDoesNotCount() async throws {
        let session = await Session(
            world(
                agents: [main("acme-main", in: "wS", "working")], failures: ["enqueue": "refused"]))

        _ = try? await session.model.send("Fix the bug", to: Target(session.workspace("wS")))

        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.working, workingOnOurRequest: false))
    }
}

@MainActor
@Suite("Resend from the history")
struct ResendTests {
    @Test("a resend goes back to the original tab with the same /clear choice and the screenshots already stored")
    func resendToTab() async throws {
        let session = await Session(world(agents: [tabClaude("idle")]))
        try await session.model.send(
            "Make it bigger", images: [Data([1])], to: Target(try session.workspace("wS"), tab: try session.tab("wS:t2")),
            clearingContext: true)
        let entry = try #require(session.model.history.entries.first)

        await session.model.resend(entry)

        #expect(
            await session.mac.commands.filter { $0.hasPrefix("enqueue-pane") || $0.hasPrefix("attach") } == [
                "attach jpg", "enqueue-pane wS wS:p9 clear", "enqueue-pane wS wS:p9 clear",
            ])
        #expect(session.model.history.entries.count == 2)
        #expect(session.model.history.entries.first?.attachments == entry.attachments)
    }

    @Test("a resend to a vanished tab does not go out and says so")
    func resendToMissingTab() async throws {
        let session = await Session(world(agents: [tabClaude("idle")]))
        try await session.model.send("Make it bigger", to: Target(try session.workspace("wS"), tab: try session.tab("wS:t2")))
        let entry = try #require(session.model.history.entries.first)
        await session.mac.update { $0.tabs?.removeAll { $0.id == "wS:t2" } }

        await session.model.resend(entry)

        #expect(session.model.notice?.title == "Acme — login-2fa no longer exists")
        #expect(session.model.notice?.detail == "Copy the text from the history to send it elsewhere.")
        #expect(session.model.history.entries.count == 1)
    }

    @Test("a resend without loaded workspaces asks to wait for the Mac")
    func resendWhileUnreachable() async throws {
        var scenario = world()
        scenario.unreachable = "timed out"
        scenario.history = [
            SentRequest(
                id: UUID(), text: "Request", workspaceId: "wS", workspaceLabel: "Acme", createdAt: .now, status: .sent)
        ]
        let session = await Session(scenario)
        let entry = try #require(session.model.history.entries.first)

        await session.model.resend(entry)

        #expect(session.model.notice?.title == "Mac unreachable")
        #expect(session.model.notice?.detail == "Resend the request once the workspaces have loaded.")
    }
}

@MainActor
@Suite("Connection to the Mac")
struct ConnectionTests {
    @Test("a Mac unreachable before the first list is announced with the detail")
    func unreachableFirst() async {
        var scenario = world()
        scenario.unreachable = "192.168.1.20: timed out"
        let session = await Session(scenario)

        #expect(session.model.connection == .unreachable("Mac unreachable (192.168.1.20: timed out)"))
        #expect(session.model.workspaces.isEmpty)
    }

    @Test("once a list arrived, an unreachable Mac keeps the list and the target")
    func unreachableLater() async throws {
        let session = await Session(world())
        session.model.select(try session.workspace("wM"))
        await session.mac.update { $0.unreachable = "timed out" }

        await session.model.refresh()

        #expect(session.model.workspaces.count == 3)
        #expect(session.model.selectedTarget?.workspace.id == "wM")
        if case .unreachable = session.model.connection {
        } else {
            Issue.record("connection \(session.model.connection) instead of unreachable")
        }
    }

    @Test("on a question tap, its workspace becomes the target; without an opened link, the card offers it")
    func questionTap() async throws {
        let session = await Session(world())
        let question = try #require(
            QuestionNotification(userInfo: [
                "workspace_id": "wM", "agent": "na-ve-search-main", "session_url": "https://claude.ai/code/session_01",
            ]))

        await session.model.open(question)

        #expect(session.model.selectedTarget?.workspace.id == "wM")
        #expect(session.model.unopenedQuestion == question)
    }
}
