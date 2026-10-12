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
            .init(id: "wM", number: 3, label: "Vidéo studio"),
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
@Suite("Notice affichée après un envoi")
struct SendNoticeTests {
    @Test("vers un main prêt : le Mac vide le contexte puis transmet")
    func readyMain() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))

        try await session.model.send("Corrige le bug", to: Target(session.workspace("wS")))

        #expect(session.model.notice?.kind == .sent)
        #expect(session.model.notice?.title == "Envoyé à Acme")
        #expect(session.model.notice?.detail == "Le Mac vide le contexte de Claude, puis lui transmet la demande.")
    }

    @Test("sans agent : le Mac lance Claude dans le tab 1 sous le nom de l'agent")
    func missingAgent() async throws {
        let session = await Session(world())

        try await session.model.send("Ajoute un sous-titre", to: Target(session.workspace("wM")))

        #expect(session.model.notice?.title == "Envoyé à Vidéo studio")
        #expect(session.model.notice?.detail == "Le Mac lance Claude dans le tab 1, nommé vid-o-studio-main, puis lui transmet la demande.")
    }

    @Test("vers un agent qui travaille, qui est bloqué ou qui a déjà un envoi en file : en file")
    func busyAgent() async throws {
        let session = await Session(world(
            agents: [main("acme-main", in: "wS", "blocked"), main("home-main", in: "wA", "idle")],
            jobs: [.init(id: "j1", workspaceId: "wA", agent: "home-main", state: "queued")]))

        try await session.model.send("Après ta question", to: Target(session.workspace("wS")))
        #expect(session.model.notice?.kind == .queued)
        #expect(session.model.notice?.title == "En file pour Acme")
        #expect(session.model.notice?.detail == "Claude est occupé : la demande partira dès qu'il aura fini.")

        try await session.model.send("Après l'envoi en cours", to: Target(session.workspace("wA")))
        #expect(session.model.notice?.title == "En file pour ~")
    }

    @Test("vers un tab prêt : telle quelle sans /clear, contexte vidé avec /clear")
    func readyTab() async throws {
        let session = await Session(world(agents: [tabClaude("done")]))
        let target = Target(try session.workspace("wS"), tab: try session.tab("wS:t2"))

        try await session.model.send("Agrandis le bouton", to: target)
        #expect(session.model.notice?.title == "Envoyé à Acme — login-2fa")
        #expect(session.model.notice?.detail == "Le Mac transmet la demande telle quelle à Claude, qui garde son contexte.")

        await session.mac.update { $0.agents?[0].status = "idle" }
        await session.model.refresh()
        try await session.model.send("Repars de zéro", to: target, clearingContext: true)
        #expect(session.model.notice?.detail == "Le Mac vide le contexte de Claude, puis lui transmet la demande.")
        #expect(await session.mac.commands.filter { $0.hasPrefix("enqueue-pane") } == [
            "enqueue-pane wS wS:p9 keep", "enqueue-pane wS wS:p9 clear",
        ])
    }
}

@MainActor
@Suite("Échec d'un envoi")
struct SendFailureTests {
    @Test("un envoi refusé par le Mac remonte son erreur à l'aperçu et passe en échec dans l'historique")
    func refusedByMac() async throws {
        let session = await Session(world(failures: ["enqueue": "invalid agent name: x"]))

        await #expect(throws: MacLinkError.self) {
            try await session.model.send("Demande", to: Target(try session.workspace("wS")))
        }

        let entry = try #require(session.model.history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.error == "Commande refusée par le Mac (1) : invalid agent name: x")
    }

    @Test("un échec déjà annoncé ne l'est plus au rafraîchissement suivant")
    func announcedOnce() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wM", "idle")]))
        try await session.model.send("Mauvaise cible", to: Target(session.workspace("wS")))
        session.model.notice = nil

        await session.model.refresh()

        #expect(session.model.notice == nil)
    }
}

@MainActor
@Suite("Captures jointes à un envoi")
struct SendImagesTests {
    @Test("les captures sont posées sur le Mac une par une, puis citées par leur chemin dans la demande")
    func imagesUploadedThenCited() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))

        try await session.model.send("Le bouton déborde", images: [Data([1]), Data([2])], to: Target(session.workspace("wS")))

        let commands = await session.mac.commands.filter { $0.hasPrefix("attach") || $0.hasPrefix("enqueue") }
        #expect(commands == ["attach jpg", "attach jpg", "enqueue wS acme-main U3VwZXJEb2N1"])
        let prompt = try #require(await session.mac.prompts.first)
        #expect(prompt.contains("Le bouton déborde\n\nCaptures d'écran jointes, à lire avec Read :\n- /Users/moi/.local/state/heraldr/attachments/capture-101.jpg\n- /Users/moi/.local/state/heraldr/attachments/capture-102.jpg"))
        #expect(session.model.history.entries.first?.attachments?.count == 2)
    }

    @Test("une capture refusée fait échouer l'envoi avant le job, les captures posées restent dans l'historique")
    func refusedImage() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))
        await session.mac.hold("attach")
        let sending = Task { try await session.model.send("Deux captures", images: [Data([1]), Data([2])], to: Target(session.workspace("wS"))) }
        while !(await session.mac.isWaiting(at: "attach")) { await Task.yield() }
        await session.mac.release("attach", keepHolding: true)
        while !(await session.mac.isWaiting(at: "attach")) { await Task.yield() }
        await session.mac.update { $0.failures = ["attach": "invalid attachment size: 0"] }
        await session.mac.release("attach")

        await #expect(throws: MacLinkError.self) { try await sending.value }

        let entry = try #require(session.model.history.entries.first)
        #expect(entry.status == .failed)
        #expect(entry.attachments == ["/Users/moi/.local/state/heraldr/attachments/capture-101.jpg"])
        #expect(await session.mac.prompts.isEmpty)
    }
}

@MainActor
@Suite("Rafraîchissement de l'écran")
struct RefreshTests {
    @Test("un échec de tab.list garde la dernière liste de tabs, le reste de l'écran est mis à jour")
    func tabListFailureKeepsTabs() async throws {
        let session = await Session(world(agents: [main("acme-main", in: "wS", "idle")]))
        await session.mac.update {
            $0.failures = ["tab.list": "tab.list indisponible"]
            $0.agents?[0].status = "working"
        }

        await session.model.refresh()

        #expect(session.model.connection == .online)
        #expect(session.model.tabs.map(\.id) == ["wA:t1", "wS:t1", "wS:t2"])
        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.working, workingOnOurRequest: false))
    }

    @Test("sans liste de tabs reçue, un échec de tab.list laisse les workspaces s'afficher sans tab")
    func tabListFailureFirstTime() async throws {
        let session = await Session(world(failures: ["tab.list": "tab.list indisponible"]))

        #expect(session.model.connection == .online)
        #expect(session.model.workspaces.count == 3)
        #expect(session.model.tabs.isEmpty)
    }

    @Test("un rafraîchissement demandé pendant un autre n'est pas perdu")
    func refreshDuringRefresh() async throws {
        let session = await Session(world())
        await session.mac.hold("status")
        let first = Task { await session.model.refresh() }
        while !(await session.mac.isWaiting(at: "status")) { await Task.yield() }
        await session.mac.update { $0.workspaces?.append(.init(id: "wN", number: 4, label: "Nouveau")) }
        await session.model.refresh()
        await session.mac.release("status")

        await first.value

        #expect(session.model.workspaces.map(\.id).contains("wN"))
    }

    @Test("le tab ciblé qui disparaît de herdr rend la cible au main de son workspace")
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
@Suite("Cible qui travaille sur la demande de l'app")
struct WorkingOnOurRequestTests {
    @Test("un envoi en échec ne compte pas comme une demande en cours")
    func failedSendDoesNotCount() async throws {
        let session = await Session(world(
            agents: [main("acme-main", in: "wS", "working")], failures: ["enqueue": "refusé"]))

        _ = try? await session.model.send("Corrige le bug", to: Target(session.workspace("wS")))

        #expect(session.model.targetState(for: try session.workspace("wS")) == .agent(.working, workingOnOurRequest: false))
    }
}

@MainActor
@Suite("Renvoi depuis l'historique")
struct ResendTests {
    @Test("un renvoi repart vers le tab d'origine avec le même choix de /clear et les captures déjà posées")
    func resendToTab() async throws {
        let session = await Session(world(agents: [tabClaude("idle")]))
        try await session.model.send(
            "Agrandis", images: [Data([1])], to: Target(try session.workspace("wS"), tab: try session.tab("wS:t2")),
            clearingContext: true)
        let entry = try #require(session.model.history.entries.first)

        await session.model.resend(entry)

        #expect(await session.mac.commands.filter { $0.hasPrefix("enqueue-pane") || $0.hasPrefix("attach") } == [
            "attach jpg", "enqueue-pane wS wS:p9 clear", "enqueue-pane wS wS:p9 clear",
        ])
        #expect(session.model.history.entries.count == 2)
        #expect(session.model.history.entries.first?.attachments == entry.attachments)
    }

    @Test("un renvoi vers un tab disparu ne part pas et le dit")
    func resendToMissingTab() async throws {
        let session = await Session(world(agents: [tabClaude("idle")]))
        try await session.model.send("Agrandis", to: Target(try session.workspace("wS"), tab: try session.tab("wS:t2")))
        let entry = try #require(session.model.history.entries.first)
        await session.mac.update { $0.tabs?.removeAll { $0.id == "wS:t2" } }

        await session.model.resend(entry)

        #expect(session.model.notice?.title == "Acme — login-2fa n'existe plus")
        #expect(session.model.notice?.detail == "Copie le texte depuis l'historique pour l'envoyer ailleurs.")
        #expect(session.model.history.entries.count == 1)
    }

    @Test("un renvoi sans workspaces chargés demande d'attendre le Mac")
    func resendWhileUnreachable() async throws {
        var scenario = world()
        scenario.unreachable = "délai dépassé"
        scenario.history = [SentRequest(
            id: UUID(), text: "Demande", workspaceId: "wS", workspaceLabel: "Acme", createdAt: .now, status: .sent)]
        let session = await Session(scenario)
        let entry = try #require(session.model.history.entries.first)

        await session.model.resend(entry)

        #expect(session.model.notice?.title == "Mac injoignable")
        #expect(session.model.notice?.detail == "Renvoie la demande une fois les workspaces chargés.")
    }
}

@MainActor
@Suite("Connexion au Mac")
struct ConnectionTests {
    @Test("un Mac injoignable avant la première liste est annoncé avec le détail")
    func unreachableFirst() async {
        var scenario = world()
        scenario.unreachable = "192.168.1.20: délai dépassé"
        let session = await Session(scenario)

        #expect(session.model.connection == .unreachable("Mac injoignable (192.168.1.20: délai dépassé)"))
        #expect(session.model.workspaces.isEmpty)
    }

    @Test("une fois une liste arrivée, un Mac injoignable garde la liste et la cible")
    func unreachableLater() async throws {
        let session = await Session(world())
        session.model.select(try session.workspace("wM"))
        await session.mac.update { $0.unreachable = "délai dépassé" }

        await session.model.refresh()

        #expect(session.model.workspaces.count == 3)
        #expect(session.model.selectedTarget?.workspace.id == "wM")
        if case .unreachable = session.model.connection {} else {
            Issue.record("connexion \(session.model.connection) au lieu d'injoignable")
        }
    }

    @Test("au tap sur une question, son workspace devient la cible ; sans lien ouvert, la carte le propose")
    func questionTap() async throws {
        let session = await Session(world())
        let question = try #require(QuestionNotification(userInfo: [
            "workspace_id": "wM", "agent": "vid-o-studio-main", "session_url": "https://claude.ai/code/session_01",
        ]))

        await session.model.open(question)

        #expect(session.model.selectedTarget?.workspace.id == "wM")
        #expect(session.model.unopenedQuestion == question)
    }
}
