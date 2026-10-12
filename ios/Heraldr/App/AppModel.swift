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

    struct PresentedAnswer: Identifiable, Equatable {
        let id: String
        let question: String?
        let targetLabel: String
        var answer: Answer
        var loading: Bool
        var failure: String?
    }

    private(set) var mac: PairedMac?
    private(set) var connection: Connection = .unpaired
    private(set) var workspaces: [Workspace] = []
    private(set) var jobs: [DispatchJob] = []
    private(set) var agents: [Agent] = []
    private(set) var tabs: [Tab] = []
    private(set) var history: SendHistory {
        didSet { SendHistoryStore.save(history, to: environment.defaults) }
    }
    var selectedWorkspaceId: String?
    private(set) var selectedTabId: String?
    var notice: Notice?
    var unopenedQuestion: QuestionNotification?
    var presentedAnswer: PresentedAnswer?
    private var pushDevice: PushDevice?
    private var pushDeviceRegistered = false
    private var notificationsRequested = false

    private let environment: AppEnvironment
    private var link: (any MacTransport)?
    private var pollTask: Task<Void, Never>?
    private let lexiconKeeper: LexiconKeeper
    private var lexiconBackupTask: Task<Void, Never>?
    private let dictationJournal = DictationJournal()
    private var refreshing = false
    private var refreshRequestedWhileRefreshing = false

    init(environment: AppEnvironment = .live) {
        self.environment = environment
        history = SendHistoryStore.load(from: environment.defaults)
        lexiconKeeper = LexiconKeeper(store: environment.lexiconStore)
        if let mac = PairedMacStore.load(from: environment.defaults) {
            attach(mac)
        }
    }

    var lexicon: DictationLexicon {
        get { lexiconKeeper.lexicon }
        set {
            lexiconKeeper.update(newValue)
            scheduleLexiconBackup()
        }
    }

    var lexiconBackup: LexiconKeeper.BackupState {
        lexiconKeeper.backupState
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
            for: target.workspace, tab: target.tab, agents: agents, jobs: jobs,
            lastSentAt: history.lastAccepted(to: target)?.createdAt, now: .now)
    }

    func pair(code: String) async throws {
        let mac = try await environment.pair(code)
        PairedMacStore.save(mac, to: environment.defaults)
        attach(mac)
        lexiconKeeper.paired()
        await refresh()
    }

    func forgetMac() async {
        await link?.disconnect()
        PairedMacStore.forget(from: environment.defaults)
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
            await fetchAnswers(history.jobsAwaitingAnswer(in: newJobs), with: dispatcher)
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
        Task { await syncLexicon() }
        Task { await uploadDictationJournal() }
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
        if let url = question.sessionURL, await environment.openURL(url) {
            unopenedQuestion = nil
            return
        }
        unopenedQuestion = question
    }

    func open(_ notification: AnswerNotification) async {
        let entry = history.entry(forJob: notification.jobId)
        let label = entry?.targetLabel
            ?? workspaces.first { $0.id == notification.workspaceId }?.label
            ?? notification.workspaceId
        presentedAnswer = PresentedAnswer(
            id: notification.jobId, question: entry?.text, targetLabel: label,
            answer: entry?.answer ?? Answer(summary: notification.summary, body: ""),
            loading: entry?.answer == nil)
        guard entry?.answer == nil else { return }
        do {
            guard let link else { throw MacLinkError.unreachable("aucun Mac appairé") }
            let answer = try await Dispatcher(link: link).answer(toJob: notification.jobId)
            history.receive(answer, forJob: notification.jobId)
            guard presentedAnswer?.id == notification.jobId else { return }
            presentedAnswer?.answer = answer
            presentedAnswer?.loading = false
        } catch {
            guard presentedAnswer?.id == notification.jobId else { return }
            presentedAnswer?.loading = false
            presentedAnswer?.failure = "Réponse complète indisponible : \(error.localizedDescription)"
        }
    }

    private func fetchAnswers(_ jobIds: [String], with dispatcher: Dispatcher) async {
        for jobId in jobIds {
            guard let answer = try? await dispatcher.answer(toJob: jobId) else { continue }
            history.receive(answer, forJob: jobId)
        }
    }

    private func requestNotificationsOnce() async {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        await environment.requestNotifications()
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

    private func scheduleLexiconBackup() {
        lexiconBackupTask?.cancel()
        lexiconBackupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncLexicon()
        }
    }

    private func syncLexicon() async {
        guard let link, let restored = await lexiconKeeper.sync(with: Dispatcher(link: link).lexiconMirror) else { return }
        notice = Notice(
            kind: .sent, title: "Lexique restauré depuis le Mac",
            detail: restored > 1 ? "\(restored) termes repris de la sauvegarde." : "1 terme repris de la sauvegarde.")
    }

    func recordDictation(sent text: String, origin: ComposeView.Origin) {
        dictationJournal.record(sent: text, origin: origin)
        Task { await uploadDictationJournal() }
    }

    private func uploadDictationJournal() async {
        guard let link else { return }
        await dictationJournal.upload(with: Dispatcher(link: link).journalMirror)
    }

    func send(
        _ text: String, images: [Data] = [], uploaded: [String] = [], to target: Target, clearingContext: Bool = false
    ) async throws {
        let workspace = target.workspace
        let entryId = history.record(text, to: workspace, tab: target.tab, clearingContext: clearingContext)
        history.attach(entryId, paths: uploaded)
        let state = targetState(for: target)
        do {
            guard let link else { throw MacLinkError.unreachable("aucun Mac appairé") }
            let dispatcher = Dispatcher(link: link)
            let paneId = try target.tab.map { tab in
                guard let paneId = tab.firstClaude(in: agents)?.paneId else { throw TargetError.noClaude(target) }
                return paneId
            }
            var attachments = uploaded
            if !images.isEmpty { try await dispatcher.installScript() }
            for image in images {
                attachments.append(try await dispatcher.upload(image))
                history.attach(entryId, paths: attachments)
            }
            let jobId = if let paneId {
                try await dispatcher.send(
                    text, attachments: attachments, toPane: paneId, in: workspace, clearingContext: clearingContext)
            } else {
                try await dispatcher.send(text, attachments: attachments, to: workspace)
            }
            history.accept(entryId, jobId: jobId)
        } catch {
            history.fail(entryId, error: error.localizedDescription)
            throw error
        }
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
            try await send(
                entry.text, uploaded: entry.attachments ?? [], to: target, clearingContext: entry.clearsContext ?? false)
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

    private func attach(_ mac: PairedMac) {
        guard let link = environment.connect(mac) else { return }
        self.mac = mac
        self.link = link
        connection = .connecting
    }

    private func announceFailures(previous: [DispatchJob], current: [DispatchJob], workspaces: [Workspace]) {
        let awaitedInHistory = Set(history.entries.filter { $0.status != .failed }.compactMap(\.jobId))
        let knownFailures = Set(previous.filter { $0.state == .failed }.map(\.id)).subtracting(awaitedInHistory)
        let tracked = Set(previous.map(\.id)).union(awaitedInHistory)
        let failures = current.filter { $0.state == .failed && !knownFailures.contains($0.id) && tracked.contains($0.id) }
        guard let first = failures.first else { return }
        func label(of job: DispatchJob) -> String {
            history.entry(forJob: job.id)?.targetLabel
                ?? workspaces.first { $0.id == job.workspaceId }?.label
                ?? job.workspaceId
        }
        guard failures.count > 1 else {
            notice = Notice(kind: .failed, title: "Échec de l'envoi vers \(label(of: first))", detail: first.error ?? "erreur inconnue")
            return
        }
        notice = Notice(
            kind: .failed, title: "Échec de \(failures.count) envois",
            detail: failures.map { "\(label(of: $0)) : \($0.error ?? "erreur inconnue")" }.joined(separator: "\n"))
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
