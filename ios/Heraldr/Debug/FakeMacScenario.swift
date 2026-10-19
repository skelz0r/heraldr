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
        var dictationLanguage: String?
        var transcriptionLocales: [String]?
        var failures: [String: String]?
        var stalled: [String]?
        var notification: [String: String]?
        var notificationDelay: Double?

        static let defaultTranscriptionLocales = ["en-US", "en-GB", "fr-FR", "fr-CA", "de-DE", "es-ES", "it-IT", "ja-JP", "pt-BR", "zh-CN"]
        static let launchArgument = "-HeraldrFakeMac"
        static let environmentKey = "HERALDR_FAKE_MAC"
        static let keptForRelaunchEnvironmentKey = "HERALDR_FAKE_MAC_KEPT_FOR_RELAUNCH"
        static let keptForRelaunchDefaultsKey = "HeraldrFakeMacKeptForRelaunch"

        static func fromLaunch(_ processInfo: ProcessInfo = .processInfo, defaults: UserDefaults = .standard) -> FakeMacScenario? {
            guard let scenario = requested(by: processInfo) else {
                defer { defaults.removeObject(forKey: keptForRelaunchDefaultsKey) }
                return defaults.string(forKey: keptForRelaunchDefaultsKey).flatMap { try? decoded($0) }
            }
            if processInfo.environment[keptForRelaunchEnvironmentKey] == "1" {
                var relaunched = scenario
                relaunched.notification = nil
                defaults.set(try? relaunched.encoded(), forKey: keptForRelaunchDefaultsKey)
            } else {
                defaults.removeObject(forKey: keptForRelaunchDefaultsKey)
            }
            return scenario
        }

        private static func requested(by processInfo: ProcessInfo) -> FakeMacScenario? {
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
            "unreachable": FakeMacScenario(unreachable: "192.168.1.20: connection refused; 100.64.0.2: timed out"),
            "demo": demo,
            "empty": FakeMacScenario(workspaces: [Workspace(id: "wA", number: 1, label: "~")]),
            "connecting": FakeMacScenario(stalled: ["workspace.list"]),
            "history": withHistory,
            "question": withQuestion,
        ]

        static var withQuestion: FakeMacScenario {
            var scenario = demo
            scenario.notification = [
                "title": "Acme", "subtitle": "Export of the contacts", "body": "Which database for the export?",
                "workspace_id": "wS", "agent": "acme-main", "session_url": "https://claude.ai/code/session_01fake",
            ]
            scenario.notificationDelay = 12
            return scenario
        }

        static var withHistory: FakeMacScenario {
            var scenario = demo
            let now = Date.now
            func entry(
                _ text: String, _ workspace: Workspace, tab: Tab? = nil, minutes: Double, status: SentRequest.Status,
                job: String? = nil, error: String? = nil, attachments: [String]? = nil, answer: Answer? = nil
            ) -> SentRequest {
                SentRequest(
                    id: UUID(), text: text, workspaceId: workspace.id, workspaceLabel: workspace.label, tabId: tab?.id,
                    tabLabel: tab.map { $0.label ?? "tab \($0.number)" }, clearsContext: tab.map { _ in false },
                    attachments: attachments, createdAt: now.addingTimeInterval(-minutes * 60), status: status, jobId: job,
                    error: error, answer: answer)
            }
            let heraldr = Workspace(id: "wH", number: 2, label: "Heraldr")
            let acme = Workspace(id: "wS", number: 3, label: "Acme")
            let search = Workspace(id: "wM", number: 4, label: "Naïve search")
            let home = Workspace(id: "wA", number: 1, label: "~")
            scenario.history = [
                entry(
                    "Add a dark mode to the settings screen and check the contrast of the status dots", heraldr,
                    minutes: 2, status: .sent, job: "20261012115800-000000000004-aa"),
                entry(
                    "The Send button overflows on small screens", heraldr,
                    tab: Tab(id: "wH:t2", workspaceId: "wH", number: 2, label: "harness-qa"), minutes: 6, status: .queued,
                    job: "20261012115400-000000000003-aa", attachments: ["/Users/me/a.jpg", "/Users/me/b.jpg"]),
                entry(
                    "Fix the CSV export of invoices", acme, minutes: 40, status: .failed,
                    job: "20261012112000-000000000002-aa", error: "agent acme-main belongs to workspace wM"),
                entry(
                    "Rerun the search indexing", search, minutes: 300, status: .failed, error: SendHistory.interruptedError,
                    attachments: ["/Users/me/c.jpg"]),
                entry(
                    "How does the thumbnail cache work?", home, minutes: 90, status: .sent,
                    job: "20261012102000-000000000001-aa",
                    answer: Answer(
                        summary: "The cache is cleared on every deploy.",
                        body: "The thumbnail cache lives in `tmp/thumbnails`.\n\n- cleared on every deploy\n- rebuilt on demand",
                        receivedAt: now.addingTimeInterval(-80 * 60))),
            ]
            var lexicon = DictationLexicon()
            _ = lexicon.define("Acme", heard: ["ack me", "acne"], at: now.addingTimeInterval(-3600))
            _ = lexicon.define("herdr", heard: ["herder"], at: now)
            scenario.lexicon = lexicon
            return scenario
        }

        static var demo: FakeMacScenario {
            FakeMacScenario(
                workspaces: [
                    Workspace(id: "wA", number: 1, label: "~"),
                    Workspace(id: "wH", number: 2, label: "Heraldr"),
                    Workspace(id: "wS", number: 3, label: "Acme"),
                    Workspace(id: "wM", number: 4, label: "Naïve search"),
                    Workspace(id: "wL", number: 5, label: "local_events"),
                    Workspace(id: "wB", number: 6, label: "Blog"),
                    Workspace(id: "wK", number: 7, label: "🟡 Morris"),
                ],
                tabs: [
                    Tab(id: "wA:t1", workspaceId: "wA", number: 1, label: "claude"),
                    Tab(id: "wH:t1", workspaceId: "wH", number: 1, label: "claude"),
                    Tab(id: "wH:t2", workspaceId: "wH", number: 2, label: "harness-qa"),
                    Tab(id: "wH:t3", workspaceId: "wH", number: 3, label: "dictation-journal"),
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
                    Agent(name: "na-ve-search-main", kind: "claude", paneId: "wM:p1", workspaceId: "wM", tabId: "wM:t1", status: "done"),
                    Agent(name: "local_events-main", kind: "claude", paneId: "wL:p1", workspaceId: "wL", tabId: "wL:t1", status: "thinking"),
                    Agent(name: "w---morris-main", kind: "claude", paneId: "wK:p1", workspaceId: "wK", tabId: "wK:t1", status: "idle"),
                    Agent(name: "morris_api-main", kind: "claude", paneId: "wK:p2", workspaceId: "wK", tabId: "wK:t1", status: "idle"),
                ],
                jobs: [
                    Job(id: "20261012090000-000000000001-aa", workspaceId: "wS", agent: "acme-main", state: "queued")
                ])
        }
    }
#endif
