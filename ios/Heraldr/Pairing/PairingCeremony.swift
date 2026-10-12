import CryptoKit
import Foundation
import HeelerSSH

enum PairingError: Error, LocalizedError {
    case invalidCode(PairingCode.ParseError)
    case configOnlyCode
    case expired
    case enrollmentRefused(String)
    case enrollmentFailed(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode(let error):
            "Ce n'est pas un code d'appairage herdr (\(error.rawValue))"
        case .configOnlyCode:
            "Ce code ne contient pas de clé d'amorçage : relance heeler.pair sur le Mac"
        case .expired:
            "Le code a expiré : relance heeler.pair sur le Mac"
        case .enrollmentRefused(let reason):
            "Le Mac a refusé l'enrôlement (\(reason))"
        case .enrollmentFailed(let detail):
            "Enrôlement impossible : \(detail)"
        case .verificationFailed(let detail):
            "Le Mac n'accepte pas encore la clé de l'iPhone : \(detail)"
        }
    }
}

enum PairingCeremony {
    static let deviceKeyComment = "heraldr-ios"
    private static let maximumResponseBytes = 1024

    static func pair(code rawCode: String, deviceKey: DeviceKey, now: Date = .now) async throws -> PairedMac {
        let code: PairingCode
        do {
            code = try PairingCode(parsing: rawCode)
        } catch {
            throw PairingError.invalidCode(error)
        }
        guard let bootstrap = code.bootstrap else { throw PairingError.configOnlyCode }
        guard bootstrap.expiresAt > now else { throw PairingError.expired }

        let bootstrapKey = DeviceKey(privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: bootstrap.seed))
        let reached = try await SSHDialer.connect(
            addresses: code.addresses,
            port: code.port,
            username: code.username,
            hostKeyFingerprint: code.hostKeyFingerprint,
            identity: SSHIdentity(bootstrapKey))
        do {
            try await enroll(deviceKey, over: reached.connection)
        } catch {
            try? await reached.connection.close(timeout: .seconds(2))
            throw error
        }
        try? await reached.connection.close(timeout: .seconds(2))

        let mac = PairedMac(
            addresses: code.addresses,
            port: code.port,
            username: code.username,
            hostKeyFingerprint: code.hostKeyFingerprint
        ).preferring(reached.address)
        try await verify(mac, deviceKey: deviceKey)
        return mac
    }

    private static func enroll(_ deviceKey: DeviceKey, over connection: SSHConnection) async throws {
        let line = deviceKey.authorizedKeysLine(comment: deviceKeyComment)
        let response: Data
        do {
            response = try await connection.executeResponseLine(
                "heraldr-enroll",
                input: Data((line + "\n").utf8),
                maximumResponseBytes: maximumResponseBytes,
                timeout: .seconds(20))
        } catch {
            throw PairingError.enrollmentFailed("\(error)")
        }
        try checkEnrollment(String(decoding: response, as: UTF8.self), of: deviceKey)
    }

    static func checkEnrollment(_ response: String, of deviceKey: DeviceKey) throws(PairingError) {
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("HERDR-ENROLL:OK:") {
            let enrolled = String(text.dropFirst("HERDR-ENROLL:OK:".count))
            guard enrolled == deviceKey.fingerprint else {
                throw PairingError.enrollmentFailed("le Mac a enrôlé une autre clé (\(enrolled))")
            }
        } else if text.hasPrefix("HERDR-ENROLL:ERR:") {
            let reason = String(text.dropFirst("HERDR-ENROLL:ERR:".count))
            throw reason == "expired" ? PairingError.expired : PairingError.enrollmentRefused(reason)
        } else {
            throw PairingError.enrollmentFailed("réponse inattendue : \(text.prefix(120))")
        }
    }

    private static func verify(_ mac: PairedMac, deviceKey: DeviceKey) async throws {
        do {
            let reached = try await SSHDialer.connect(
                addresses: mac.addresses,
                port: mac.port,
                username: mac.username,
                hostKeyFingerprint: mac.hostKeyFingerprint,
                identity: SSHIdentity(deviceKey))
            try? await reached.connection.close(timeout: .seconds(2))
        } catch {
            throw PairingError.verificationFailed(error.localizedDescription)
        }
    }
}
