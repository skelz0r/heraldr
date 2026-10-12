import CryptoKit
import Foundation
import Testing

@testable import Heraldr

@Suite("Pairing refused before any contact with the Mac")
struct PairingCeremonyTests {
    private let deviceKey = DeviceKey(privateKey: .init())

    private func vector(named name: String) throws -> PairingCodeVectors.Valid {
        try #require(try PairingCodeVectors.shared().valid.first { $0.name == name })
    }

    @Test("an expired code is refused, so an outdated bootstrap key is never presented")
    func expiredCode() async throws {
        let code = try vector(named: "with bootstrap seed and expiry")
        let expiry = Date(timeIntervalSince1970: TimeInterval(code.payload.expiresAt!))

        await #expect {
            try await PairingCeremony.pair(code: code.code, deviceKey: deviceKey, now: expiry)
        } throws: { error in
            guard case PairingError.expired = error else { return false }
            return true
        }
    }

    @Test("a code without bootstrap key is refused: it cannot enroll the iPhone")
    func configOnlyCode() async throws {
        let code = try vector(named: "config-only single LAN IPv4, default port")

        await #expect {
            try await PairingCeremony.pair(code: code.code, deviceKey: deviceKey)
        } throws: { error in
            guard case PairingError.configOnlyCode = error else { return false }
            return true
        }
    }
}

@Suite("Mac response to the enrollment of the iPhone key")
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

    @Test("the Mac confirms the fingerprint of the iPhone key: enrollment accepted")
    func enrolled() {
        #expect(refusal("HERDR-ENROLL:OK:\(deviceKey.fingerprint)\n") == nil)
    }

    @Test("the Mac enrolled another key than the iPhone one: refused with the received fingerprint")
    func otherKey() {
        #expect(refusal("HERDR-ENROLL:OK:SHA256:other") == "Enrollment failed: the Mac enrolled another key (SHA256:other)")
    }

    @Test("the Mac refuses the enrollment: its reason is shown")
    func refused() {
        #expect(refusal("HERDR-ENROLL:ERR:already-used") == "The Mac refused the enrollment (already-used)")
    }

    @Test("the code expired during enrollment: same text as a code expired before")
    func expiredDuringEnrollment() {
        #expect(refusal("HERDR-ENROLL:ERR:expired") == "The code expired: run heeler.pair again on the Mac")
    }

    @Test("a response outside the enrollment protocol is refused")
    func unexpected() {
        #expect(refusal("Welcome to macOS") == "Enrollment failed: unexpected response: Welcome to macOS")
    }
}

@Suite("Pinned Mac host key")
struct PinnedHostKeyTests {
    @Test("an SSH server presenting another key than the QR one is refused before any authentication")
    func otherHostKeyRefused() async {
        await #expect {
            _ = try await SSHDialer.connect(
                addresses: ["127.0.0.1"], port: 22, username: "heraldr-tests",
                hostKeyFingerprint: "SHA256:qr-key", identity: SSHIdentity(DeviceKey(privateKey: .init())))
        } throws: { error in
            guard case MacLinkError.hostKeyChanged(let presented) = error else { return false }
            return presented.hasPrefix("SHA256:") && presented != "SHA256:qr-key"
        }
    }
}
