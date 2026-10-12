import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case unpaired
        case connecting
        case online
        case unreachable(String)
    }

    struct Notice: Identifiable, Equatable {
        enum Kind { case sent, queued, failed }
        let id = UUID()
        let kind: Kind
        let title: String
        let detail: String
    }

    enum TargetState: Equatable {
        case missing
        case tabWithoutClaude
        case sending
        case agent(AgentStatus, workingOnOurRequest: Bool)

        var acceptsImmediately: Bool {
            switch self {
            case .missing: true
            case .tabWithoutClaude, .sending: false
            case .agent(let status, _): status.isReady
            }
        }

        static func resolve(
            for workspace: Workspace, tab: Tab? = nil, agents: [Agent], jobs: [DispatchJob], lastSentAt: Date?, now: Date
        ) -> TargetState {
            let agent: Agent
            if let tab {
                guard let claude = tab.firstClaude(in: agents) else { return .tabWithoutClaude }
                if jobs.contains(where: { $0.workspaceId == workspace.id && $0.agent == claude.paneId && $0.isPending }) {
                    return .sending
                }
                agent = claude
            } else {
                let name = AgentName.forWorkspace(label: workspace.label)
                if jobs.contains(where: { $0.workspaceId == workspace.id && $0.agent == name && $0.isPending }) { return .sending }
                guard let main = agents.first(where: { $0.name == name && $0.workspaceId == workspace.id }) else {
                    return .missing
                }
                agent = main
            }
            let recentlySent = lastSentAt.map { now.timeIntervalSince($0) < 3600 } ?? false
            return .agent(agent.agentStatus, workingOnOurRequest: recentlySent)
        }

        var dotStatus: AgentStatus {
            switch self {
            case .missing, .tabWithoutClaude: .unknown
            case .sending: .working
            case .agent(let status, _): status
            }
        }
    }

    private(set) var mac: PairedMac?
    private(set) var connection: Connection = .unpaired
    private(set) var workspaces: [Workspace] = []
    private(set) var jobs: [DispatchJob] = []
    private(set) var agents: [Agent] = []
    private(set) var tabs: [Tab] = []
    private(set) var history = SendHistoryStore.load() {
        didSet { SendHistoryStore.save(history) }
    }
    private var lastSentAt: [String: Date] = [:]
    var selectedWorkspaceId: String?
    private(set) var selectedTabId: String?
    var notice: Notice?
    var unopenedQuestion: QuestionNotification?
    private var pushDevice: PushDevice?
    private var pushDeviceRegistered = false
    private var notificationsRequested = false

    private var link: MacLink?
    private var deviceKey: DeviceKey?
    private var pollTask: Task<Void, Never>?
    private var refreshing = false
    private var refreshRequestedWhileRefreshing = false

    init() {
        if let mac = PairedMacStore.load(), let key = try? DeviceKeyStore.load() {
            attach(mac, deviceKey: key)
        }
    }

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceId } ?? workspaces.first
    }

    var selectedTarget: Target? {
        selectedWorkspace.map { target(in: $0, tabId: selectedTabId) }
    }

    func target(in workspace: Workspace, tabId: String?) -> Target {
        Target(workspace, tab: tabs.first { $0.id == tabId && $0.workspaceId == workspace.id && !$0.isMain })
    }

    func select(_ workspace: Workspace, tab: Tab? = nil) {
        selectedWorkspaceId = workspace.id
        selectedTabId = tab?.id
        schedulePolling()
    }

    func claudeTabs(of workspace: Workspace) -> [Tab] {
        tabs.filter { $0.workspaceId == workspace.id && !$0.isMain && $0.firstClaude(in: agents) != nil }
    }

    func pendingJobs(for workspace: Workspace) -> [DispatchJob] {
        jobs.filter { $0.workspaceId == workspace.id && $0.isPending }
    }

    func pendingJobs(for tab: Tab) -> [DispatchJob] {
        guard let paneId = tab.firstClaude(in: agents)?.paneId else { return [] }
        return jobs.filter { $0.workspaceId == tab.workspaceId && $0.agent == paneId && $0.isPending }
    }

    func targetState(for workspace: Workspace) -> TargetState {
        targetState(for: Target(workspace))
    }

    func targetState(for target: Target) -> TargetState {
        .resolve(
            for: target.workspace, tab: target.tab, agents: agents, jobs: jobs, lastSentAt: lastSentAt[target.id], now: .now)
    }

    func pair(code: String) async throws {
        let key = try DeviceKeyStore.loadOrCreate()
        let mac = try await PairingCeremony.pair(code: code, deviceKey: key)
        PairedMacStore.save(mac)
        attach(mac, deviceKey: key)
        await refresh()
    }

    func forgetMac() async {
        await link?.disconnect()
        PairedMacStore.forget()
        link = nil
        mac = nil
        workspaces = []
        jobs = []
        pushDeviceRegistered = false
        connection = .unpaired
    }

    func resetTargetToHome() {
        selectedWorkspaceId = workspaces.first(where: \.isHome)?.id ?? workspaces.first?.id
        selectedTabId = nil
    }

    func refresh() async {
        guard !refreshing else {
            refreshRequestedWhileRefreshing = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshRequestedWhileRefreshing = false
            await refreshOnce()
        } while refreshRequestedWhileRefreshing
    }

    private func refreshOnce() async {
        guard let link else { return }
        if workspaces.isEmpty { connection = .connecting }
        do {
            let herdr = HerdrClient(link: link)
            let dispatcher = Dispatcher(link: link)
            let newWorkspaces = try await herdr.workspaces()
            let newAgents = try await herdr.agents()
            let newTabs = (try? await herdr.tabs()) ?? tabs
            let newJobs = try await dispatcher.jobs()
            announceFailures(previous: jobs, current: newJobs, workspaces: newWorkspaces)
            history.follow(newJobs)
            workspaces = newWorkspaces
            agents = newAgents
            tabs = newTabs
            jobs = newJobs
            if selectedWorkspaceId == nil || !newWorkspaces.contains(where: { $0.id == selectedWorkspaceId }) {
                resetTargetToHome()
            }
            if let selectedTabId, !newTabs.contains(where: { $0.id == selectedTabId }) {
                self.selectedTabId = nil
            }
            connection = .online
        } catch {
            connection = .unreachable(error.localizedDescription)
            schedulePolling()
            return
        }
        Task { await requestNotificationsOnce() }
        await registerPushDeviceIfNeeded()
        schedulePolling()
    }

    func registerPush(_ device: PushDevice) async {
        guard device != pushDevice else { return }
        pushDevice = device
        pushDeviceRegistered = false
        await registerPushDeviceIfNeeded()
    }

    func open(_ question: QuestionNotification) async {
        selectedWorkspaceId = question.workspaceId
        selectedTabId = nil
        if let url = question.sessionURL, await UIApplication.shared.open(url, options: [.universalLinksOnly: true]) {
            unopenedQuestion = nil
            return
        }
        unopenedQuestion = question
    }

    private func requestNotificationsOnce() async {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func registerPushDeviceIfNeeded() async {
        guard let link, let pushDevice, !pushDeviceRegistered else { return }
        do {
            try await Dispatcher(link: link).registerPush(pushDevice)
            pushDeviceRegistered = true
        } catch {
            notice = Notice(kind: .failed, title: "Notifications non installées sur le Mac", detail: error.localizedDescription)
        }
    }

    func send(_ text: String, to target: Target, clearingContext: Bool = false) async throws {
        let workspace = target.workspace
        let entryId = history.record(text, to: workspace, tab: target.tab, clearingContext: clearingContext)
        let state = targetState(for: target)
        do {
            guard let link else { throw MacLinkError.unreachable("aucun Mac appairé") }
            let dispatcher = Dispatcher(link: link)
            let jobId: String
            if let tab = target.tab {
                guard let paneId = tab.firstClaude(in: agents)?.paneId else { throw TargetError.noClaude(target) }
                jobId = try await dispatcher.send(text, toPane: paneId, in: workspace, clearingContext: clearingContext)
            } else {
                jobId = try await dispatcher.send(text, to: workspace)
            }
            history.accept(entryId, jobId: jobId)
        } catch {
            history.fail(entryId, error: error.localizedDescription)
            throw error
        }
        lastSentAt[target.id] = .now
        notice = Self.notice(afterSendingTo: target, state: state, clearingContext: clearingContext)
        await refresh()
    }

    private static func notice(afterSendingTo target: Target, state: TargetState, clearingContext: Bool) -> Notice {
        let label = target.tab == nil ? target.workspace.label : target.label
        switch state {
        case .missing:
            return Notice(kind: .sent, title: "Envoyé à \(label)", detail: "Le Mac lance Claude dans le tab 1, nommé \(AgentName.forWorkspace(label: target.workspace.label)), puis lui transmet la demande.")
        case .agent(let status, _) where status.isReady && (target.tab == nil || clearingContext):
            return Notice(kind: .sent, title: "Envoyé à \(label)", detail: "Le Mac vide le contexte de Claude, puis lui transmet la demande.")
        case .agent(let status, _) where status.isReady:
            return Notice(kind: .sent, title: "Envoyé à \(label)", detail: "Le Mac transmet la demande telle quelle à Claude, qui garde son contexte.")
        default:
            return Notice(kind: .queued, title: "En file pour \(label)", detail: "Claude est occupé : la demande partira dès qu'il aura fini.")
        }
    }

    func resend(_ entry: SentRequest) async {
        await refresh()
        guard !workspaces.isEmpty else {
            notice = Notice(kind: .failed, title: "Mac injoignable", detail: "Renvoie la demande une fois les workspaces chargés.")
            return
        }
        guard
            let workspace = workspaces.first(where: { $0.id == entry.workspaceId }),
            entry.tabId == nil || tabs.contains(where: { $0.id == entry.tabId })
        else {
            notice = Notice(
                kind: .failed, title: "\(entry.targetLabel) n'existe plus",
                detail: "Copie le texte depuis l'historique pour l'envoyer ailleurs.")
            return
        }
        let target = target(in: workspace, tabId: entry.tabId)
        do {
            try await send(entry.text, to: target, clearingContext: entry.clearsContext ?? false)
        } catch {
            notice = Notice(kind: .failed, title: "Échec de l'envoi vers \(entry.targetLabel)", detail: error.localizedDescription)
        }
    }

    func removeFromHistory(_ id: SentRequest.ID) {
        history.remove(id)
    }

    func pause() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func attach(_ mac: PairedMac, deviceKey: DeviceKey) {
        self.mac = mac
        self.deviceKey = deviceKey
        link = MacLink(mac: mac, deviceKey: deviceKey)
        connection = .connecting
    }

    private func announceFailures(previous: [DispatchJob], current: [DispatchJob], workspaces: [Workspace]) {
        let known = Set(previous.filter { $0.state == .failed }.map(\.id))
        let tracked = Set(previous.map(\.id))
        guard let failed = current.first(where: { $0.state == .failed && !known.contains($0.id) && tracked.contains($0.id) }) else {
            return
        }
        let label = history.entries.first { $0.jobId == failed.id }?.targetLabel
            ?? workspaces.first { $0.id == failed.workspaceId }?.label
            ?? failed.workspaceId
        notice = Notice(kind: .failed, title: "Échec de l'envoi vers \(label)", detail: failed.error ?? "erreur inconnue")
    }

    private func schedulePolling() {
        pollTask?.cancel()
        let watchedTabWorking = selectedTarget?.tab?.firstClaude(in: agents)?.agentStatus == .working
        guard jobs.contains(where: \.isPending) || watchedTabWorking || agents.contains(where: { $0.name != nil && $0.agentStatus == .working }) else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}

enum TargetError: Error, LocalizedError {
    case noClaude(Target)

    var errorDescription: String? {
        switch self {
        case .noClaude(let target): "Plus de Claude dans \(target.label) : relance-le sur le Mac."
        }
    }
}
