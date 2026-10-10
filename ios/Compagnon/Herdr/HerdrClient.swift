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
    let agentStatus: AgentStatus

    static let homeLabel = "~"

    var isHome: Bool { label == Self.homeLabel }

    var displayName: String { label }

    enum CodingKeys: String, CodingKey {
        case id = "workspace_id"
        case number
        case label
        case agentStatus = "agent_status"
    }

    static func ordered(_ workspaces: [Workspace]) -> [Workspace] {
        workspaces.sorted { lhs, rhs in
            if lhs.isHome != rhs.isHome { return lhs.isHome }
            return lhs.number < rhs.number
        }
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

struct HerdrClient: Sendable {
    let link: MacLink

    func workspaces() async throws -> [Workspace] {
        let list: WorkspaceList = try await call("workspace.list")
        return Workspace.ordered(list.workspaces)
    }

    private func call<Result: Decodable>(_ method: String) async throws -> Result {
        let request = "{\"id\":\"compagnon:\(UUID().uuidString)\",\"method\":\"\(method)\",\"params\":{}}\n"
        let response = try await link.exchangeWithHerdr(Data(request.utf8))
        let envelope = try JSONDecoder().decode(HerdrEnvelope<Result>.self, from: response)
        if let error = envelope.error { throw error }
        guard let result = envelope.result else {
            throw HerdrError(code: "empty_response", message: "réponse vide pour \(method)")
        }
        return result
    }
}
