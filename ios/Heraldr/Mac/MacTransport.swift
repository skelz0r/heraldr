import Foundation

struct CommandResult: Sendable, Equatable {
    let exitStatus: Int32
    let stdout: Data
    let stderr: Data

    var output: String { String(decoding: stdout, as: UTF8.self) }
    var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

protocol MacTransport: Sendable {
    func run(_ command: String, input: Data, timeout: Duration, replayable: Bool) async throws -> CommandResult
    func exchangeWithHerdr(_ request: Data) async throws -> Data
    func disconnect() async
}

extension MacTransport {
    func run(_ command: String, input: Data = Data(), replayable: Bool = true) async throws -> CommandResult {
        try await run(command, input: input, timeout: .seconds(20), replayable: replayable)
    }
}
