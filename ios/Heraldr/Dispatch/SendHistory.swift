import Foundation

struct Answer: Codable, Equatable, Sendable {
    let summary: String
    let body: String
    let receivedAt: Date

    init(summary: String, body: String, receivedAt: Date = .now) {
        self.summary = summary
        self.body = body
        self.receivedAt = receivedAt
    }

    init?(scriptOutput: String, receivedAt: Date = .now) {
        let parts = scriptOutput.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let summary = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !summary.isEmpty else { return nil }
        let body = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        self.init(summary: summary, body: body.isEmpty ? summary : body, receivedAt: receivedAt)
    }
}

struct SentRequest: Codable, Identifiable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case sending
        case queued
        case sent
        case failed
    }

    let id: UUID
    let text: String
    let workspaceId: String
    let workspaceLabel: String
    var tabId: String?
    var tabLabel: String?
    var clearsContext: Bool?
    var attachments: [String]?
    let createdAt: Date
    var status: Status
    var jobId: String?
    var error: String?
    var answer: Answer?

    var targetLabel: String {
        tabLabel.map { "\(workspaceLabel) — \($0)" } ?? workspaceLabel
    }
}

struct SendHistory: Codable, Equatable, Sendable {
    static let capacity = 20
    static let interruptedError = "Envoi interrompu avant la réponse du Mac."

    private(set) var entries: [SentRequest] = []

    var tasks: [SentRequest] { entries.filter { $0.answer == nil } }
    var questions: [SentRequest] { entries.filter { $0.answer != nil } }

    mutating func record(
        _ text: String, to workspace: Workspace, tab: Tab? = nil, clearingContext: Bool = false, at date: Date = .now
    ) -> SentRequest.ID {
        let entry = SentRequest(
            id: UUID(), text: text, workspaceId: workspace.id, workspaceLabel: workspace.label,
            tabId: tab?.id, tabLabel: tab?.displayName, clearsContext: tab.map { _ in clearingContext },
            createdAt: date, status: .sending)
        entries.insert(entry, at: 0)
        keepLatest()
        return entry.id
    }

    mutating func attach(_ id: SentRequest.ID, paths: [String]) {
        update(id) { $0.attachments = paths.isEmpty ? nil : paths }
    }

    mutating func accept(_ id: SentRequest.ID, jobId: String) {
        update(id) {
            $0.status = .queued
            $0.jobId = jobId.isEmpty ? nil : jobId
        }
    }

    mutating func fail(_ id: SentRequest.ID, error: String) {
        update(id) {
            $0.status = .failed
            $0.error = error
        }
    }

    mutating func remove(_ id: SentRequest.ID) {
        entries.removeAll { $0.id == id }
    }

    mutating func follow(_ jobs: [DispatchJob]) {
        for index in entries.indices {
            guard let job = jobs.first(where: { $0.id == entries[index].jobId }) else { continue }
            switch job.state {
            case .queued, .sending: entries[index].status = .queued
            case .sent: entries[index].status = .sent
            case .failed:
                entries[index].status = .failed
                entries[index].error = job.error ?? "erreur inconnue"
            }
        }
    }

    func jobsAwaitingAnswer(in jobs: [DispatchJob]) -> [String] {
        jobs.filter(\.answered).map(\.id).filter { jobId in
            entries.contains { $0.jobId == jobId && $0.answer == nil }
        }
    }

    func lastAccepted(to target: Target) -> SentRequest? {
        entries.first { entry in
            entry.workspaceId == target.workspace.id && entry.tabId == target.tab?.id
                && (entry.status == .queued || entry.status == .sent)
        }
    }

    func entry(forJob jobId: String) -> SentRequest? {
        entries.first { $0.jobId == jobId }
    }

    mutating func receive(_ answer: Answer, forJob jobId: String) {
        guard let index = entries.firstIndex(where: { $0.jobId == jobId }) else { return }
        entries[index].answer = answer
        keepLatest()
    }

    mutating func interruptPendingSends() {
        for index in entries.indices where entries[index].status == .sending {
            entries[index].status = .failed
            entries[index].error = Self.interruptedError
        }
    }

    private mutating func keepLatest() {
        var keptTasks = 0
        var keptQuestions = 0
        entries = entries.filter { entry in
            if entry.answer == nil {
                keptTasks += 1
                return keptTasks <= Self.capacity
            }
            keptQuestions += 1
            return keptQuestions <= Self.capacity
        }
    }

    private mutating func update(_ id: SentRequest.ID, _ change: (inout SentRequest) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }
}

enum SendHistoryStore {
    private static let key = "send-history"

    static func load(from defaults: UserDefaults = .standard) -> SendHistory {
        guard
            let data = defaults.data(forKey: key),
            var history = try? JSONDecoder().decode(SendHistory.self, from: data)
        else { return SendHistory() }
        history.interruptPendingSends()
        return history
    }

    static func save(_ history: SendHistory, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(history), forKey: key)
    }
}
