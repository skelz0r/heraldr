#if DEBUG
    import Foundation

    actor FakeMac: MacTransport {
        static let pairedMac = PairedMac(
            addresses: ["192.168.1.20", "100.64.0.2"], port: 22, username: "me", hostKeyFingerprint: "SHA256:fake")

        private(set) var scenario: FakeMacScenario
        private(set) var commands: [String] = []
        private(set) var prompts: [String] = []
        private(set) var lexiconBackup: Data?
        private(set) var replies: [String] = []
        private var sequence = 100
        private var holds: Set<String> = []
        private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
        private var staleAt: String?

        init(_ scenario: FakeMacScenario) {
            self.scenario = scenario
            holds = Set(scenario.stalled ?? [])
        }

        func goStale(failingAt step: String) {
            staleAt = step
        }

        func update(_ change: @Sendable (inout FakeMacScenario) -> Void) {
            change(&scenario)
        }

        func setJob(_ id: String, state: String, error: String? = nil) {
            guard let index = scenario.jobs?.firstIndex(where: { $0.id == id }) else { return }
            scenario.jobs?[index].state = state
            scenario.jobs?[index].error = error
        }

        func hold(_ step: String) {
            holds.insert(step)
        }

        func release(_ step: String, keepHolding: Bool = false) {
            if !keepHolding { holds.remove(step) }
            waiting.removeValue(forKey: step)?.resume()
        }

        func isWaiting(at step: String) -> Bool {
            waiting[step] != nil
        }

        func run(_ command: String, input: Data, timeout: Duration, replayable: Bool) async throws -> CommandResult {
            let arguments = Self.dispatchArguments(of: command)
            let subcommand = arguments.first ?? "install"
            try await pass(subcommand)
            commands.append(([subcommand] + arguments.dropFirst()).joined(separator: " "))
            let result = respond(to: subcommand, arguments: arguments, input: input)
            try await pass("\(subcommand):done")
            return result
        }

        private func respond(to subcommand: String, arguments: [String], input: Data) -> CommandResult {
            if let failure = scenario.failures?[subcommand] {
                return Self.failure(failure)
            }
            switch subcommand {
            case "status":
                return .success(statusOutput())
            case "enqueue" where arguments.count == 3:
                guard let label = Data(base64Encoded: arguments[2]).map({ String(decoding: $0, as: UTF8.self) }), !label.isEmpty
                else { return Self.failure("2:invalid label") }
                let mains = mainAgents(of: arguments[1])
                let named = AgentName.forWorkspace(label: label)
                guard mains.count <= 1 || mains.contains(named) else {
                    return Self.failure("2:several -main agents in \(arguments[1]): \(mains.joined(separator: " "))")
                }
                let agent = mains.count == 1 ? mains[0] : named
                guard !input.isEmpty else { return Self.failure("2:empty prompt") }
                return .success(enqueue(workspaceId: arguments[1], agent: agent, prompt: input))
            case "enqueue-pane" where arguments.count == 4:
                guard arguments[2].wholeMatch(of: #/[A-Za-z0-9]+:[A-Za-z0-9]+/#) != nil else {
                    return Self.failure("2:invalid pane: \(arguments[2])")
                }
                guard ["clear", "keep"].contains(arguments[3]), !input.isEmpty else { return Self.failure("2:usage") }
                return .success(enqueue(workspaceId: arguments[1], agent: arguments[2], prompt: input))
            case "start" where arguments.count == 3:
                guard let label = Data(base64Encoded: arguments[2]).map({ String(decoding: $0, as: UTF8.self) }), !label.isEmpty
                else { return Self.failure("2:invalid label") }
                let mains = mainAgents(of: arguments[1])
                let named = AgentName.forWorkspace(label: label)
                guard mains.count <= 1 || mains.contains(named) else {
                    return Self.failure("2:several -main agents in \(arguments[1]): \(mains.joined(separator: " "))")
                }
                return .success(start(workspaceId: arguments[1], agent: mains.count == 1 ? mains[0] : named))
            case "enqueue", "enqueue-pane", "start":
                return Self.failure("2:usage")
            case "attach":
                guard ["jpg", "png"].contains(arguments.dropFirst().first ?? "") else { return Self.failure("2:invalid extension") }
                guard !input.isEmpty, input.count <= 20_000_000 else { return Self.failure("2:invalid attachment size: \(input.count)") }
                sequence += 1
                return .success("/Users/me/.local/state/heraldr/attachments/capture-\(sequence).jpg\n")
            case "read-answer" where arguments.count == 2:
                guard let answer = scenario.answers?[arguments[1]] else {
                    return CommandResult(exitStatus: 2, stdout: Data(), stderr: Data("no answer for \(arguments[1])".utf8))
                }
                return .success(answer)
            case "register-push" where input.isEmpty:
                return Self.failure("2:empty hook")
            case "reply" where arguments.count == 4:
                return reply(pane: arguments[1], questionId: arguments[2], option: arguments[3], hook: input)
            case "reply":
                return Self.failure("2:usage")
            case "lexicon-get":
                return CommandResult(exitStatus: 0, stdout: lexiconBackup ?? Data(), stderr: Data())
            case "lexicon-put":
                lexiconBackup = input
                return .success("")
            default:
                return .success("")
            }
        }

        func exchangeWithHerdr(_ request: Data) async throws -> Data {
            let method = (try? JSONSerialization.jsonObject(with: request) as? [String: Any])?["method"] as? String ?? ""
            try await pass(method)
            commands.append(method)
            if let failure = scenario.failures?[method] {
                return Self.json(["id": "cli", "error": ["code": "fake_failure", "message": failure]])
            }
            switch method {
            case "workspace.list":
                return Self.json(["id": "cli", "result": ["type": "workspace_list", "workspaces": workspacesPayload()]])
            case "agent.list":
                return Self.json(["id": "cli", "result": ["type": "agent_list", "agents": agentsPayload()]])
            case "tab.list":
                return Self.json(["id": "cli", "result": ["type": "tab_list", "tabs": tabsPayload()]])
            default:
                return Self.json(["id": "cli", "error": ["code": "unknown_method", "message": "unknown method \(method)"]])
            }
        }

        func disconnect() async {
            staleAt = nil
        }

        private func pass(_ step: String) async throws {
            if holds.contains(step) {
                await withCheckedContinuation { waiting[step] = $0 }
            }
            if staleAt == step {
                staleAt = nil
                throw MacLinkError.connectionLost
            }
            if let unreachable = scenario.unreachable {
                throw MacLinkError.unreachable(unreachable)
            }
        }

        private func reply(pane: String, questionId: String, option: String, hook: Data) -> CommandResult {
            guard pane.wholeMatch(of: #/[A-Za-z0-9]+:[A-Za-z0-9]+/#) != nil else { return Self.failure("2:invalid pane: \(pane)") }
            guard questionId.wholeMatch(of: #/[0-9a-f]{16}/#) != nil else { return Self.failure("2:invalid question: \(questionId)") }
            guard let number = Int(option), option.wholeMatch(of: #/[1-9]/#) != nil else { return Self.failure("2:invalid option: \(option)") }
            guard !hook.isEmpty else { return Self.failure("2:empty hook") }
            guard let index = scenario.agents?.firstIndex(where: { $0.paneId == pane }), let agent = scenario.agents?[index] else {
                return Self.failure("3:Claude is no longer waiting for this answer")
            }
            guard agent.name?.hasSuffix(AgentName.suffix) == true else { return Self.failure("2:pane \(pane) is not a -main agent") }
            guard agent.status == "blocked" else { return Self.failure("3:Claude is no longer waiting for this answer") }
            guard let question = agent.question, question.id == questionId else { return Self.failure("3:the question on the Mac changed") }
            guard question.options.contains(number) else { return Self.failure("2:option \(number) cannot be answered from the iPhone") }
            replies.append("\(pane) \(number)")
            scenario.agents?[index].status = "working"
            scenario.agents?[index].question = nil
            return .success("")
        }

        private func mainAgents(of workspaceId: String) -> [String] {
            (scenario.agents ?? []).compactMap { agent in
                guard agent.workspaceId == workspaceId, let name = agent.name, name.hasSuffix(AgentName.suffix) else { return nil }
                return name
            }
        }

        private func enqueue(workspaceId: String, agent: String, prompt: Data) -> String {
            prompts.append(String(decoding: prompt, as: UTF8.self))
            sequence += 1
            let id = "20261012120000-\(String(format: "%012d", sequence))-fa\(sequence)"
            let (state, error) = outcome(workspaceId: workspaceId, agent: agent)
            scenario.jobs = (scenario.jobs ?? []) + [FakeMacScenario.Job(id: id, workspaceId: workspaceId, agent: agent, state: state, error: error)]
            if state == "sent" {
                startWorking(agent)
            }
            return id + "\n"
        }

        private func start(workspaceId: String, agent: String) -> String {
            sequence += 1
            let id = "20261012120000-\(String(format: "%012d", sequence))-fa\(sequence)"
            let owner = scenario.agents?.first { $0.name == agent }?.workspaceId
            let error: String? =
                if let owner, owner != workspaceId { "agent \(agent) belongs to workspace \(owner)" } else { scenario.startFailure }
            if owner == nil && error == nil {
                let tab = scenario.tabs?.first { $0.workspaceId == workspaceId && $0.number == 1 }
                scenario.agents =
                    (scenario.agents ?? []) + [
                        FakeMacScenario.Agent(
                            name: agent, kind: "claude", paneId: "\(workspaceId):p\(sequence)", workspaceId: workspaceId, tabId: tab?.id,
                            status: "idle")
                    ]
            }
            scenario.jobs =
                (scenario.jobs ?? []) + [
                    FakeMacScenario.Job(
                        id: id, workspaceId: workspaceId, agent: agent, state: error == nil ? "sent" : "failed", error: error, kind: "start")
                ]
            return id + "\n"
        }

        private func outcome(workspaceId: String, agent: String) -> (String, String?) {
            let agents = scenario.agents ?? []
            let isPane = agent.contains(":")
            let pending = (scenario.jobs ?? []).contains { $0.agent == agent && ($0.state == "queued" || $0.state == "sending") }
            guard let target = agents.first(where: { isPane ? $0.paneId == agent : $0.name == agent }) else {
                return isPane ? ("failed", "no Claude left in pane \(agent)") : (pending ? "queued" : "sent", nil)
            }
            if isPane && target.kind != "claude" {
                return ("failed", "no Claude left in pane \(agent)")
            }
            if isPane, let name = target.name {
                return ("failed", "pane \(agent) is agent \(name): target it by name")
            }
            if let owner = target.workspaceId, owner != workspaceId {
                return ("failed", isPane ? "pane \(agent) belongs to workspace \(owner)" : "agent \(agent) belongs to workspace \(owner)")
            }
            return ["idle", "done"].contains(target.status) && !pending ? ("sent", nil) : ("queued", nil)
        }

        private func startWorking(_ agent: String) {
            guard let index = scenario.agents?.firstIndex(where: { $0.name == agent || $0.paneId == agent }) else { return }
            scenario.agents?[index].status = "working"
        }

        private func statusOutput() -> String {
            (scenario.jobs ?? []).map { job in
                [
                    job.id, job.workspaceId, job.agent, job.state, job.error ?? "", job.answered == true ? "answered" : "",
                    job.kind ?? "send",
                ]
                .joined(separator: "\t")
            }
            .joined(separator: "\n") + "\n"
        }

        private func workspacesPayload() -> [[String: Any]] {
            (scenario.workspaces ?? []).map { workspace in
                [
                    "workspace_id": workspace.id, "number": workspace.number, "label": workspace.label,
                    "agent_status": "working", "focused": false, "pane_count": 2, "tab_count": 2,
                ]
            }
        }

        private func tabsPayload() -> [[String: Any]] {
            (scenario.tabs ?? []).map { tab in
                var payload: [String: Any] = [
                    "tab_id": tab.id, "workspace_id": tab.workspaceId, "number": tab.number,
                    "agent_status": "idle", "focused": false, "pane_count": 1,
                ]
                payload["label"] = tab.label
                return payload
            }
        }

        private func agentsPayload() -> [[String: Any]] {
            (scenario.agents ?? []).map { agent in
                var payload: [String: Any] = [
                    "agent_status": agent.status, "focused": false, "revision": 3, "cwd": "/Users/me/work",
                    "agent_session": ["agent": "claude", "kind": "id", "value": "session"],
                ]
                payload["name"] = agent.name
                payload["agent"] = agent.kind
                payload["pane_id"] = agent.paneId
                payload["workspace_id"] = agent.workspaceId
                payload["tab_id"] = agent.tabId
                return payload
            }
        }

        private static func json(_ object: [String: Any]) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }

        static func dispatchArguments(of command: String) -> [String] {
            guard let range = command.range(of: "dispatch.sh\" ", options: .backwards) else { return [] }
            return shellWords(String(command[range.upperBound...]))
        }

        private static func shellWords(_ text: String) -> [String] {
            var words: [String] = []
            var current = ""
            var quoted = false
            var inWord = false
            for character in text {
                if quoted {
                    if character == "'" { quoted = false } else { current.append(character) }
                } else if character == "'" {
                    quoted = true
                    inWord = true
                } else if character == "\\" {
                    inWord = true
                } else if character == " " {
                    if inWord { words.append(current) }
                    current = ""
                    inWord = false
                } else {
                    current.append(character)
                    inWord = true
                }
            }
            if inWord { words.append(current) }
            return words
        }
    }

    extension FakeMac {
        static func failure(_ scripted: String) -> CommandResult {
            let parts = scripted.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let status = Int32(parts[0]) else {
                return CommandResult(exitStatus: 1, stdout: Data(), stderr: Data(scripted.utf8))
            }
            return CommandResult(exitStatus: status, stdout: Data(), stderr: Data(parts[1].utf8))
        }
    }

    extension CommandResult {
        static func success(_ output: String) -> CommandResult {
            CommandResult(exitStatus: 0, stdout: Data(output.utf8), stderr: Data())
        }
    }
#endif
