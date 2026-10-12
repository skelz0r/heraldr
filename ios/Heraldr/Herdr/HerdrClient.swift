import Foundation

enum AgentStatus: String, Codable, Sendable {
    case idle
    case working
    case blocked
    case done
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentStatus(rawValue: raw) ?? .unknown
    }

    var isReady: Bool { self == .idle || self == .done }
}

struct Workspace: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let label: String

    static let homeLabel = "~"
    static let homeNumber = 1

    var isHome: Bool { number == Self.homeNumber }

    var displayName: String { label }

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id"
        case number
        case label
    }

    static func ordered(_ workspaces: [Workspace]) -> [Workspace] {
        workspaces.sorted { lhs, rhs in
            if lhs.isHome != rhs.isHome { return lhs.isHome }
            return lhs.number < rhs.number
        }
    }
}

struct Tab: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let workspaceId: String
    let number: Int
    let label: String?

    static let mainNumber = 1
    static let mainName = "main"

    var isMain: Bool { number == Self.mainNumber }

    var displayName: String {
        if isMain { return Self.mainName }
        guard let label, !label.isEmpty else { return "tab \(number)" }
        return label
    }

    func firstClaude(in agents: [Agent]) -> Agent? {
        agents.first { $0.tabId == id && $0.isClaude && $0.name == nil && $0.paneId != nil }
    }

    enum CodingKeys: String, CodingKey {
        case id = "tab_id"
        case workspaceId = "workspace_id"
        case number
        case label
    }
}

struct Agent: Decodable, Equatable, Sendable {
    let name: String?
    let kind: String?
    let paneId: String?
    let workspaceId: String
    let tabId: String
    let agentStatus: AgentStatus

    var isClaude: Bool { kind == "claude" }

    enum CodingKeys: String, CodingKey {
        case name
        case kind = "agent"
        case paneId = "pane_id"
        case workspaceId = "workspace_id"
        case tabId = "tab_id"
        case agentStatus = "agent_status"
    }
}

struct HerdrError: Error, LocalizedError, Decodable {
    let code: String
    let message: String

    var errorDescription: String? { "herdr : \(message) (\(code))" }
}

private struct HerdrEnvelope<Payload: Decodable>: Decodable {
    let result: Payload?
    let error: HerdrError?
}

private struct WorkspaceList: Decodable {
    let workspaces: [Workspace]
}

private struct AgentList: Decodable {
    let agents: [Agent]
}

private struct TabList: Decodable {
    let tabs: [Tab]
}

struct HerdrClient: Sendable {
    let link: any MacTransport

    func workspaces() async throws -> [Workspace] {
        let list: WorkspaceList = try await call("workspace.list")
        return Workspace.ordered(list.workspaces)
    }

    func agents() async throws -> [Agent] {
        let list: AgentList = try await call("agent.list")
        return list.agents
    }

    func tabs() async throws -> [Tab] {
        let list: TabList = try await call("tab.list")
        return list.tabs.sorted { $0.number < $1.number }
    }

    private func call<Result: Decodable>(_ method: String) async throws -> Result {
        let request = "{\"id\":\"heraldr:\(UUID().uuidString)\",\"method\":\"\(method)\",\"params\":{}}\n"
        let response = try await link.exchangeWithHerdr(Data(request.utf8))
        let envelope = try JSONDecoder().decode(HerdrEnvelope<Result>.self, from: response)
        if let error = envelope.error { throw error }
        guard let result = envelope.result else {
            throw HerdrError(code: "empty_response", message: "réponse vide pour \(method)")
        }
        return result
    }
}
