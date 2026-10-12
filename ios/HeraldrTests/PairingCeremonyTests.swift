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

@Suite("Réponse du Mac à l'enrôlement de la clé de l'iPhone")
struct EnrollmentResponseTests {
    private let deviceKey = DeviceKey(privateKey: .init())

    private func refusal(_ response: String) -> String? {
        do {
            try PairingCeremony.checkEnrollment(response, of: deviceKey)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test("le Mac confirme l'empreinte de la clé de l'iPhone : enrôlement accepté")
    func enrolled() {
        #expect(refusal("HERDR-ENROLL:OK:\(deviceKey.fingerprint)\n") == nil)
    }

    @Test("le Mac a enrôlé une autre clé que celle de l'iPhone : refusé avec l'empreinte reçue")
    func otherKey() {
        #expect(refusal("HERDR-ENROLL:OK:SHA256:autre") == "Enrôlement impossible : le Mac a enrôlé une autre clé (SHA256:autre)")
    }

    @Test("le Mac refuse l'enrôlement : sa raison est affichée")
    func refused() {
        #expect(refusal("HERDR-ENROLL:ERR:already-used") == "Le Mac a refusé l'enrôlement (already-used)")
    }

    @Test("le code a expiré pendant l'enrôlement : même texte qu'un code expiré avant")
    func expiredDuringEnrollment() {
        #expect(refusal("HERDR-ENROLL:ERR:expired") == "Le code a expiré : relance heeler.pair sur le Mac")
    }

    @Test("une réponse qui n'est pas du protocole d'enrôlement est refusée")
    func unexpected() {
        #expect(refusal("Welcome to macOS") == "Enrôlement impossible : réponse inattendue : Welcome to macOS")
    }
}

@Suite("Clé hôte du Mac épinglée")
struct PinnedHostKeyTests {
    @Test("un serveur SSH qui présente une autre clé que celle du QR est refusé avant toute authentification")
    func otherHostKeyRefused() async {
        await #expect {
            _ = try await SSHDialer.connect(
                addresses: ["127.0.0.1"], port: 22, username: "heraldr-tests",
                hostKeyFingerprint: "SHA256:clé-du-qr", identity: SSHIdentity(DeviceKey(privateKey: .init())))
        } throws: { error in
            guard case MacLinkError.hostKeyChanged(let presented) = error else { return false }
            return presented.hasPrefix("SHA256:") && presented != "SHA256:clé-du-qr"
        }
    }
}
