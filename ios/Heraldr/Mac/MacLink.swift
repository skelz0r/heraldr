import Foundation
import HeelerSSH

enum MacLinkError: Error, LocalizedError {
    case unreachable(String)
    case hostKeyChanged(presented: String)
    case authenticationRefused
    case tailscaleSSH
    case commandFailed(status: Int32, stderr: String)
    case connectionLost
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unreachable(let detail):
            "Mac unreachable (\(detail))"
        case .hostKeyChanged(let presented):
            "The Mac's key changed (\(presented)): pair again"
        case .authenticationRefused:
            "The Mac refuses this iPhone's key: pair again"
        case .tailscaleSSH:
            "Tailscale SSH answered instead of the Mac's sshd: turn it off (RunSSH: false)"
        case .commandFailed(let status, let stderr):
            "Command refused by the Mac (\(status)): \(stderr)"
        case .connectionLost:
            "Connection to the Mac lost"
        case .timedOut:
            "The Mac did not answer in time"
        }
    }
}

struct SSHIdentity: Sendable {
    let publicKeyBlob: Data
    let sign: @Sendable (Data) throws -> Data

    init(_ key: DeviceKey) {
        publicKeyBlob = key.publicKeyBlob
        sign = { challenge in try key.sign(challenge) }
    }
}

enum SSHDialer {
    static let perAddressTimeout: Duration = .seconds(6)
    static let authenticationTimeout: Duration = .seconds(10)

    static func connect(
        addresses: [String],
        port: Int,
        username: String,
        hostKeyFingerprint: String,
        identity: SSHIdentity
    ) async throws -> (connection: SSHConnection, address: String) {
        var attempts: [String] = []
        var sawTailscale = false
        var mismatchedKey: String?
        for address in addresses {
            try Task.checkCancellation()
            guard let sshPort = UInt16(exactly: port) else { throw MacLinkError.unreachable("port \(port)") }
            let connection: SSHConnection
            do {
                connection = try await SSHConnection.connect(
                    to: SSHEndpoint(host: address, port: sshPort),
                    timeout: perAddressTimeout)
            } catch {
                attempts.append("\(address): \(error)")
                continue
            }
            if connection.serverIdentification?.hasPrefix("SSH-2.0-Tailscale") == true {
                sawTailscale = true
                try? await connection.close(timeout: .seconds(2))
                continue
            }
            let presented = SSHFingerprint.of(publicKeyBlob: connection.hostKey.key)
            guard presented == hostKeyFingerprint else {
                try? await connection.close(timeout: .seconds(2))
                mismatchedKey = presented
                continue
            }
            do {
                try await connection.authenticate(
                    username: username,
                    publicKey: identity.publicKeyBlob,
                    signer: identity.sign,
                    timeout: authenticationTimeout)
                return (connection, address)
            } catch SSHError.authenticationFailed {
                try? await connection.close(timeout: .seconds(2))
                throw MacLinkError.authenticationRefused
            } catch {
                try? await connection.close(timeout: .seconds(2))
                attempts.append("\(address): \(error)")
            }
        }
        if let mismatchedKey { throw MacLinkError.hostKeyChanged(presented: mismatchedKey) }
        if sawTailscale { throw MacLinkError.tailscaleSSH }
        throw MacLinkError.unreachable(attempts.joined(separator: "; "))
    }
}

actor MacLink: MacTransport {
    private(set) var mac: PairedMac
    private let identity: SSHIdentity
    private let defaults: UserDefaults
    private var connection: SSHConnection?
    private var home: String?

    init(mac: PairedMac, deviceKey: DeviceKey, defaults: UserDefaults) {
        self.mac = mac
        self.identity = SSHIdentity(deviceKey)
        self.defaults = defaults
    }

    func run(_ command: String, input: Data, timeout: Duration) async throws -> CommandResult {
        let result = try await onLiveConnection { connection in
            try await connection.execute(command, input: input, timeout: timeout)
        }
        return CommandResult(exitStatus: result.exitStatus, stdout: result.stdout, stderr: result.stderr)
    }

    func herdrSocketPath() async throws -> String {
        if let home { return "\(home)/.config/herdr/herdr.sock" }
        let result = try await run("printf %s \"$HOME\"")
        let resolved = result.output
        guard result.exitStatus == 0, resolved.hasPrefix("/") else {
            throw MacLinkError.commandFailed(status: result.exitStatus, stderr: "HOME not found")
        }
        home = resolved
        return "\(resolved)/.config/herdr/herdr.sock"
    }

    func exchangeWithHerdr(_ request: Data) async throws -> Data {
        let socketPath = try await herdrSocketPath()
        return try await onLiveConnection { connection in
            try await connection.exchangeStreamLocal(socketPath: socketPath, request: request, timeout: .seconds(10))
        }
    }

    func disconnect() async {
        let dropped = connection
        connection = nil
        try? await dropped?.close(timeout: .seconds(2))
    }

    private func onLiveConnection<T: Sendable>(_ operation: (SSHConnection) async throws -> T) async throws -> T {
        let current = try await liveConnection()
        do {
            return try await operation(current)
        } catch let error as SSHError where Self.signalsLostConnection(error) {
            throw MacLinkError.connectionLost
        } catch SSHError.timedOut {
            throw MacLinkError.timedOut
        }
    }

    private static func signalsLostConnection(_ error: SSHError) -> Bool {
        [.connectionInvalidated, .connectionFailed, .unexpectedEOF, .channelFailed].contains(error)
    }

    private func liveConnection() async throws -> SSHConnection {
        if let connection, await connection.isConnected {
            return connection
        }
        connection = nil
        let dialed = try await SSHDialer.connect(
            addresses: mac.addresses,
            port: mac.port,
            username: mac.username,
            hostKeyFingerprint: mac.hostKeyFingerprint,
            identity: identity)
        if dialed.address != mac.addresses.first {
            mac = mac.preferring(dialed.address)
            PairedMacStore.save(mac, to: defaults)
        }
        connection = dialed.connection
        return dialed.connection
    }
}
