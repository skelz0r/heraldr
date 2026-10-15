import Foundation

actor RedialingTransport: MacTransport {
    private let link: any MacTransport
    private var linkGeneration = 0

    init(_ link: any MacTransport) {
        self.link = link
    }

    func run(_ command: String, input: Data, timeout: Duration) async throws -> CommandResult {
        try await redialingOnce { link in
            try await link.run(command, input: input, timeout: timeout)
        }
    }

    func exchangeWithHerdr(_ request: Data) async throws -> Data {
        try await redialingOnce { link in
            try await link.exchangeWithHerdr(request)
        }
    }

    func disconnect() async {
        linkGeneration += 1
        await link.disconnect()
    }

    private func redialingOnce<T: Sendable>(_ operation: @Sendable (any MacTransport) async throws -> T) async throws -> T {
        let generation = linkGeneration
        do {
            return try await operation(link)
        } catch MacLinkError.connectionLost {
            if generation == linkGeneration {
                await disconnect()
            }
            return try await operation(link)
        }
    }
}
