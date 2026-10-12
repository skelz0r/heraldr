#if DEBUG
import Foundation

actor FakeMac: MacTransport {
    static let pairedMac = PairedMac(
        addresses: ["192.168.1.20", "100.64.0.2"], port: 22, username: "moi", hostKeyFingerprint: "SHA256:faux")

    private(set) var scenario: FakeMacScenario
    private(set) var commands: [String] = []
    private(set) var prompts: [String] = []
    private(set) var lexiconBackup: Data?
    private var sequence = 100
    private var holds: Set<String> = []
    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]

    init(_ scenario: FakeMacScenario) {
        self.scenario = scenario
        holds = Set(scenario.stalled ?? [])
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

    func run(_ command: String, input: Data, timeout: Duration) async throws -> CommandResult {
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
            return CommandResult(exitStatus: 1, stdout: Data(), stderr: Data(failure.utf8))
        }
        switch subcommand {
        case "status":
            return .success(statusOutput())
        case "enqueue" where arguments.count == 4:
            return .success(enqueue(workspaceId: arguments[1], agent: arguments[2], prompt: input))
        case "enqueue-pane" where arguments.count == 4:
            return .success(enqueue(workspaceId: arguments[1], agent: arguments[2], prompt: input))
        case "attach":
            sequence += 1
            return .success("/Users/moi/.local/state/heraldr/attachments/capture-\(sequence).jpg\n")
        case "read-answer" where arguments.count == 2:
            guard let answer = scenario.answers?[arguments[1]] else {
                return CommandResult(exitStatus: 2, stdout: Data(), stderr: Data("pas de réponse pour \(arguments[1])".utf8))
            }
            return .success(answer)
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
            return Self.json(["id": "cli", "error": ["code": "unknown_method", "message": "méthode inconnue \(method)"]])
        }
    }

    func disconnect() async {}

    private func pass(_ step: String) async throws {
        if holds.contains(step) {
            await withCheckedContinuation { waiting[step] = $0 }
        }
        if let unreachable = scenario.unreachable {
            throw MacLinkError.unreachable(unreachable)
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

    private func outcome(workspaceId: String, agent: String) -> (String, String?) {
        let agents = scenario.agents ?? []
        let isPane = agent.contains(":")
        guard let target = agents.first(where: { isPane ? $0.paneId == agent : $0.name == agent }) else {
            return isPane ? ("failed", "plus de Claude dans le pane \(agent)") : ("sent", nil)
        }
        if isPane && target.kind != "claude" {
            return ("failed", "plus de Claude dans le pane \(agent)")
        }
        if let owner = target.workspaceId, owner != workspaceId {
            return ("failed", isPane ? "le pane \(agent) appartient au workspace \(owner)" : "l'agent \(agent) appartient au workspace \(owner)")
        }
        let pending = (scenario.jobs ?? []).contains { $0.agent == agent && ($0.state == "queued" || $0.state == "sending") }
        return ["idle", "done"].contains(target.status) && !pending ? ("sent", nil) : ("queued", nil)
    }

    private func startWorking(_ agent: String) {
        guard let index = scenario.agents?.firstIndex(where: { $0.name == agent || $0.paneId == agent }) else { return }
        scenario.agents?[index].status = "working"
    }

    private func statusOutput() -> String {
        (scenario.jobs ?? []).map { job in
            [job.id, job.workspaceId, job.agent, job.state, job.error ?? "", job.answered == true ? "answered" : ""]
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
                "agent_status": agent.status, "focused": false, "revision": 3, "cwd": "/Users/moi/work",
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

extension CommandResult {
    static func success(_ output: String) -> CommandResult {
        CommandResult(exitStatus: 0, stdout: Data(output.utf8), stderr: Data())
    }
}
#endif
