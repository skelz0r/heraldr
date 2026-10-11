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
        case sending
        case agent(AgentStatus, workingOnOurRequest: Bool)

        var acceptsImmediately: Bool {
            switch self {
            case .missing: true
            case .sending: false
            case .agent(let status, _): status.isReady
            }
        }

        static func resolve(
            for workspace: Workspace, agents: [Agent], jobs: [DispatchJob], lastSentAt: Date?, now: Date
        ) -> TargetState {
            if jobs.contains(where: { $0.workspaceId == workspace.id && $0.isPending }) { return .sending }
            let name = AgentName.forWorkspace(label: workspace.label)
            guard let agent = agents.first(where: { $0.name == name && $0.workspaceId == workspace.id }) else {
                return .missing
            }
            let recentlySent = lastSentAt.map { now.timeIntervalSince($0) < 3600 } ?? false
            return .agent(agent.agentStatus, workingOnOurRequest: recentlySent)
        }

        var dotStatus: AgentStatus {
            switch self {
            case .missing: .unknown
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
    private(set) var history = SendHistoryStore.load() {
        didSet { SendHistoryStore.save(history) }
    }
    private var lastSentAt: [String: Date] = [:]
    var selectedWorkspaceId: String?
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

    func pendingJobs(for workspace: Workspace) -> [DispatchJob] {
        jobs.filter { $0.workspaceId == workspace.id && $0.isPending }
    }

    func targetState(for workspace: Workspace) -> TargetState {
        .resolve(for: workspace, agents: agents, jobs: jobs, lastSentAt: lastSentAt[workspace.id], now: .now)
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
            let newJobs = try await dispatcher.jobs()
            announceFailures(previous: jobs, current: newJobs, workspaces: newWorkspaces)
            history.follow(newJobs)
            workspaces = newWorkspaces
            agents = newAgents
            jobs = newJobs
            if selectedWorkspaceId == nil || !newWorkspaces.contains(where: { $0.id == selectedWorkspaceId }) {
                resetTargetToHome()
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

    func send(_ text: String, to workspace: Workspace) async throws {
        let entryId = history.record(text, to: workspace)
        let state = targetState(for: workspace)
        do {
            guard let link else { throw MacLinkError.unreachable("aucun Mac appairé") }
            let jobId = try await Dispatcher(link: link).send(text, to: workspace)
            history.accept(entryId, jobId: jobId)
        } catch {
            history.fail(entryId, error: error.localizedDescription)
            throw error
        }
        lastSentAt[workspace.id] = .now
        let agent = AgentName.forWorkspace(label: workspace.label)
        switch state {
        case .missing:
            notice = Notice(kind: .sent, title: "Envoyé à \(workspace.label)", detail: "Le Mac lance \(agent) dans le tab 1, puis lui transmet la demande.")
        case .agent(let status, _) where status.isReady:
            notice = Notice(kind: .sent, title: "Envoyé à \(workspace.label)", detail: "Le Mac vide le contexte de \(agent), puis lui transmet la demande.")
        default:
            notice = Notice(kind: .queued, title: "En file pour \(workspace.label)", detail: "\(agent) est occupé : la demande partira dès qu'il aura fini.")
        }
        await refresh()
    }

    func resend(_ entry: SentRequest) async {
        await refresh()
        guard !workspaces.isEmpty else {
            notice = Notice(kind: .failed, title: "Mac injoignable", detail: "Renvoie la demande une fois les workspaces chargés.")
            return
        }
        guard let workspace = workspaces.first(where: { $0.id == entry.workspaceId }) else {
            notice = Notice(
                kind: .failed, title: "\(entry.workspaceLabel) n'existe plus",
                detail: "Copie le texte depuis l'historique pour l'envoyer ailleurs.")
            return
        }
        do {
            try await send(entry.text, to: workspace)
        } catch {
            notice = Notice(kind: .failed, title: "Échec de l'envoi vers \(workspace.label)", detail: error.localizedDescription)
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
        let label = workspaces.first { $0.id == failed.workspaceId }?.label ?? failed.workspaceId
        notice = Notice(kind: .failed, title: "Échec de l'envoi vers \(label)", detail: failed.error ?? "erreur inconnue")
    }

    private func schedulePolling() {
        pollTask?.cancel()
        guard jobs.contains(where: \.isPending) || agents.contains(where: { $0.name != nil && $0.agentStatus == .working }) else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
