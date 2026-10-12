import Foundation
import Testing

@testable import Heraldr

struct PairingCodeVectors: Decodable {
    let valid: [Valid]
    let invalid: [Invalid]

    struct Valid: Decodable, CustomTestStringConvertible {
        let name: String
        let code: String
        let payload: Payload
        let decodeOnly: Bool?

        var testDescription: String { name }
    }

    struct Payload: Decodable {
        let addresses: [String]
        let port: Int
        let username: String
        let hostKeyFingerprint: String
        let bootstrapSeed: String?
        let expiresAt: Int?
    }

    struct Invalid: Decodable, CustomTestStringConvertible {
        let name: String
        let code: String
        let error: String

        var testDescription: String { name }
    }

    static func shared() throws -> PairingCodeVectors {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "pairing-code-v1", withExtension: "json"))
        return try JSONDecoder().decode(PairingCodeVectors.self, from: Data(contentsOf: url))
    }

    private final class BundleMarker {}
}

@Suite("HERDR-PAIR:1 pairing code, test vectors shared with the Heeler plugin")
struct PairingCodeTests {
    @Test("a valid code decodes to the expected payload", arguments: try PairingCodeVectors.shared().valid)
    func decodesValidVector(vector: PairingCodeVectors.Valid) throws {
        let code = try PairingCode(parsing: vector.code)

        #expect(code.addresses == vector.payload.addresses)
        #expect(code.port == vector.payload.port)
        #expect(code.username == vector.payload.username)
        #expect(code.hostKeyFingerprint == vector.payload.hostKeyFingerprint)
        #expect(code.bootstrap?.seed == vector.payload.bootstrapSeed.flatMap(Base64URL.decode))
        #expect(code.bootstrap.map { Int($0.expiresAt.timeIntervalSince1970) } == vector.payload.expiresAt)
    }

    @Test("a canonical code re-encodes identically", arguments: try PairingCodeVectors.shared().valid.filter { $0.decodeOnly != true })
    func roundTripsCanonicalVector(vector: PairingCodeVectors.Valid) throws {
        #expect(try PairingCode(parsing: vector.code).canonicalCode == vector.code)
    }

    @Test("an invalid code is refused with the expected error", arguments: try PairingCodeVectors.shared().invalid)
    func rejectsInvalidVector(vector: PairingCodeVectors.Invalid) {
        #expect(throws: PairingCode.ParseError(rawValue: vector.error)!) {
            try PairingCode(parsing: vector.code)
        }
    }
}
