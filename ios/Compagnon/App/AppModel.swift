import Foundation
import Observation

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

    private(set) var mac: PairedMac?
    private(set) var connection: Connection = .unpaired
    private(set) var workspaces: [Workspace] = []
    private(set) var jobs: [DispatchJob] = []
    var selectedWorkspaceId: String?
    var notice: Notice?

    private var link: MacLink?
    private var deviceKey: DeviceKey?
    private var pollTask: Task<Void, Never>?
    private var refreshing = false

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
        connection = .unpaired
    }

    func resetTargetToHome() {
        selectedWorkspaceId = workspaces.first(where: \.isHome)?.id ?? workspaces.first?.id
    }

    func refresh() async {
        guard let link, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if workspaces.isEmpty { connection = .connecting }
        do {
            let herdr = HerdrClient(link: link)
            let dispatcher = Dispatcher(link: link)
            let newWorkspaces = try await herdr.workspaces()
            let newJobs = try await dispatcher.jobs()
            announceFailures(previous: jobs, current: newJobs, workspaces: newWorkspaces)
            workspaces = newWorkspaces
            jobs = newJobs
            if selectedWorkspaceId == nil || !newWorkspaces.contains(where: { $0.id == selectedWorkspaceId }) {
                resetTargetToHome()
            }
            connection = .online
        } catch {
            connection = .unreachable(error.localizedDescription)
        }
        schedulePolling()
    }

    func send(_ text: String, to workspace: Workspace) async throws {
        guard let link else { throw MacLinkError.unreachable("aucun Mac appairé") }
        let busy = !(workspaces.first { $0.id == workspace.id }?.agentStatus.isReady ?? true)
        _ = try await Dispatcher(link: link).send(text, to: workspace)
        notice = busy
            ? Notice(kind: .queued, title: "En file pour \(workspace.label)", detail: "L'agent travaille : l'envoi partira dès qu'il aura fini.")
            : Notice(kind: .sent, title: "Envoyé à \(workspace.label)", detail: "Contexte vidé, demande transmise à \(AgentName.forWorkspace(label: workspace.label)).")
        await refresh()
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
        guard jobs.contains(where: \.isPending) || workspaces.contains(where: { $0.agentStatus == .working }) else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
}
