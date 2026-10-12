#if DEBUG
import Foundation

struct FakeMacScenario: Codable, Sendable {
    struct Workspace: Codable, Sendable {
        var id: String
        var number: Int
        var label: String
    }

    struct Tab: Codable, Sendable {
        var id: String
        var workspaceId: String
        var number: Int
        var label: String?
    }

    struct Agent: Codable, Sendable {
        var name: String?
        var kind: String?
        var paneId: String?
        var workspaceId: String?
        var tabId: String?
        var status: String
    }

    struct Job: Codable, Sendable {
        var id: String
        var workspaceId: String
        var agent: String
        var state: String
        var error: String?
        var answered: Bool?
    }

    var paired: Bool?
    var unreachable: String?
    var workspaces: [Workspace]?
    var tabs: [Tab]?
    var agents: [Agent]?
    var jobs: [Job]?
    var answers: [String: String]?
    var history: [SentRequest]?
    var lexicon: DictationLexicon?
    var failures: [String: String]?

    static let launchArgument = "-HeraldrFakeMac"
    static let environmentKey = "HERALDR_FAKE_MAC"

    static func fromLaunch(_ processInfo: ProcessInfo = .processInfo) -> FakeMacScenario? {
        if let json = processInfo.environment[environmentKey], let scenario = try? decoded(json) {
            return scenario
        }
        let arguments = processInfo.arguments
        guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) else { return nil }
        return presets[arguments[index + 1]]
    }

    static func decoded(_ json: String) throws -> FakeMacScenario {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FakeMacScenario.self, from: Data(json.utf8))
    }

    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

extension FakeMacScenario {
    static let presets: [String: FakeMacScenario] = [
        "unpaired": FakeMacScenario(paired: false),
        "unreachable": FakeMacScenario(unreachable: "192.168.1.20: connexion refusée ; 100.64.0.2: délai dépassé"),
        "demo": demo,
        "empty": FakeMacScenario(workspaces: [Workspace(id: "wA", number: 1, label: "~")]),
    ]

    static var demo: FakeMacScenario {
        FakeMacScenario(
            workspaces: [
                Workspace(id: "wA", number: 1, label: "~"),
                Workspace(id: "wH", number: 2, label: "Heraldr"),
                Workspace(id: "wS", number: 3, label: "Acme"),
                Workspace(id: "wM", number: 4, label: "Vidéo studio"),
                Workspace(id: "wL", number: 5, label: "local_events"),
                Workspace(id: "wB", number: 6, label: "Blog"),
            ],
            tabs: [
                Tab(id: "wA:t1", workspaceId: "wA", number: 1, label: "claude"),
                Tab(id: "wH:t1", workspaceId: "wH", number: 1, label: "claude"),
                Tab(id: "wH:t2", workspaceId: "wH", number: 2, label: "harness-qa"),
                Tab(id: "wH:t3", workspaceId: "wH", number: 3, label: "journal-dictee"),
                Tab(id: "wH:t4", workspaceId: "wH", number: 4, label: nil),
                Tab(id: "wS:t1", workspaceId: "wS", number: 1, label: "claude"),
                Tab(id: "wM:t1", workspaceId: "wM", number: 1, label: "claude"),
                Tab(id: "wL:t1", workspaceId: "wL", number: 1, label: "claude"),
            ],
            agents: [
                Agent(name: "home-main", kind: "claude", paneId: "wA:p1", workspaceId: "wA", tabId: "wA:t1", status: "idle"),
                Agent(name: "heraldr-main", kind: "claude", paneId: "wH:p1", workspaceId: "wH", tabId: "wH:t1", status: "working"),
                Agent(name: nil, kind: "claude", paneId: "wH:p5", workspaceId: "wH", tabId: "wH:t2", status: "idle"),
                Agent(name: nil, kind: "claude", paneId: "wH:p6", workspaceId: "wH", tabId: "wH:t3", status: "working"),
                Agent(name: nil, kind: "claude", paneId: "wH:p7", workspaceId: "wH", tabId: "wH:t4", status: "blocked"),
                Agent(name: "acme-main", kind: "claude", paneId: "wS:p1", workspaceId: "wS", tabId: "wS:t1", status: "blocked"),
                Agent(name: "vid-o-studio-main", kind: "claude", paneId: "wM:p1", workspaceId: "wM", tabId: "wM:t1", status: "done"),
                Agent(name: "local_events-main", kind: "claude", paneId: "wL:p1", workspaceId: "wL", tabId: "wL:t1", status: "thinking"),
            ],
            jobs: [
                Job(id: "20261012090000-000000000001-aa", workspaceId: "wS", agent: "acme-main", state: "queued"),
            ])
    }
}
#endif
