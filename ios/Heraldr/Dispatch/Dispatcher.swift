import Foundation
import HeelerSSH

struct DispatchJob: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case queued
        case sending
        case sent
        case failed
    }

    let id: String
    let workspaceId: String
    let agent: String
    let state: State
    let error: String?

    var isPending: Bool { state == .queued || state == .sending }

    static func parse(statusOutput: String) -> [DispatchJob] {
        statusOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let state = State(rawValue: fields[3]) else { return nil }
            let error = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil
            return DispatchJob(id: fields[0], workspaceId: fields[1], agent: fields[2], state: state, error: error)
        }
    }
}

struct Dispatcher: Sendable {
    let link: MacLink

    private static let stateDirectory = "\"$HOME/.local/state/heraldr\""
    private static let script = "\"$HOME/.local/state/heraldr/dispatch.sh\""

    static let bundledScript: Data = {
        guard
            let url = Bundle.main.url(forResource: "dispatch", withExtension: "sh"),
            let data = try? Data(contentsOf: url)
        else { fatalError("dispatch.sh absent du bundle") }
        return data
    }()

    func send(_ text: String, to workspace: Workspace) async throws -> String {
        try await installScript()
        let agent = AgentName.forWorkspace(label: workspace.label)
        let label = Data(workspace.label.utf8).base64EncodedString()
        let command = "/bin/sh \(Self.script) enqueue \(quoted(workspace.id)) \(quoted(agent)) \(quoted(label))"
        let result = try await link.run(command, input: Data(PromptEnvelope.wrap(text).utf8))
        guard result.exitStatus == 0 else { throw failure(result) }
        return String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func jobs() async throws -> [DispatchJob] {
        let result = try await link.run("[ -f \(Self.script) ] && /bin/sh \(Self.script) status || true")
        guard result.exitStatus == 0 else { throw failure(result) }
        return DispatchJob.parse(statusOutput: String(decoding: result.stdout, as: UTF8.self))
    }

    private func installScript() async throws {
        let incoming = "\(Self.stateDirectory)/incoming-$$.sh"
        let command = "mkdir -p \(Self.stateDirectory) && cat > \(incoming) && /bin/sh \(incoming) install < \(incoming); rc=$?; rm -f \(incoming); exit $rc"
        let result = try await link.run(command, input: Self.bundledScript)
        guard result.exitStatus == 0 else { throw failure(result) }
    }

    private func quoted(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func failure(_ result: SSHExecResult) -> MacLinkError {
        .commandFailed(status: result.exitStatus, stderr: String(decoding: result.stderr, as: UTF8.self))
    }
}
