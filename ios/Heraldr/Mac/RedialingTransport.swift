import Foundation

struct RedialingTransport: MacTransport {
    let link: any MacTransport

    init(_ link: any MacTransport) {
        self.link = link
    }

    func run(_ command: String, input: Data, timeout: Duration, replayable: Bool) async throws -> CommandResult {
        do {
            return try await link.run(command, input: input, timeout: timeout, replayable: replayable)
        } catch MacLinkError.connectionLost where replayable {
            return try await link.run(command, input: input, timeout: timeout, replayable: replayable)
        }
    }

    func exchangeWithHerdr(_ request: Data) async throws -> Data {
        do {
            return try await link.exchangeWithHerdr(request)
        } catch MacLinkError.connectionLost {
            return try await link.exchangeWithHerdr(request)
        }
    }

    func disconnect() async {
        await link.disconnect()
    }
}
