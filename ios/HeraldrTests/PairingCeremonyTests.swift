import Foundation
import Testing
@testable import Heraldr

@Suite("Appairage refusé avant tout contact avec le Mac")
struct PairingCeremonyTests {
    private let deviceKey = DeviceKey(privateKey: .init())

    private func vector(named name: String) -> PairingCodeVectors.Valid {
        PairingCodeVectors.shared.valid.first { $0.name == name }!
    }

    @Test("un code expiré est refusé, pour ne jamais présenter une clé d'amorçage périmée")
    func expiredCode() async {
        let code = vector(named: "with bootstrap seed and expiry")
        let expiry = Date(timeIntervalSince1970: TimeInterval(code.payload.expiresAt!))

        await #expect {
            try await PairingCeremony.pair(code: code.code, deviceKey: deviceKey, now: expiry)
        } throws: { error in
            guard case PairingError.expired = error else { return false }
            return true
        }
    }

    @Test("un code sans clé d'amorçage est refusé : il ne permet pas d'enrôler l'iPhone")
    func configOnlyCode() async {
        let code = vector(named: "config-only single LAN IPv4, default port")

        await #expect {
            try await PairingCeremony.pair(code: code.code, deviceKey: deviceKey)
        } throws: { error in
            guard case PairingError.configOnlyCode = error else { return false }
            return true
        }
    }
}
