import Foundation
import Testing
@testable import Compagnon

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

    static let shared: PairingCodeVectors = {
        let url = Bundle(for: BundleMarker.self).url(forResource: "pairing-code-v1", withExtension: "json")!
        return try! JSONDecoder().decode(PairingCodeVectors.self, from: Data(contentsOf: url))
    }()

    private final class BundleMarker {}
}

@Suite("Code d'appairage HERDR-PAIR:1, vecteurs de test partagés avec le plugin Heeler")
struct PairingCodeTests {
    @Test("un code valide se décode vers le payload attendu", arguments: PairingCodeVectors.shared.valid)
    func decodesValidVector(vector: PairingCodeVectors.Valid) throws {
        let code = try PairingCode(parsing: vector.code)

        #expect(code.addresses == vector.payload.addresses)
        #expect(code.port == vector.payload.port)
        #expect(code.username == vector.payload.username)
        #expect(code.hostKeyFingerprint == vector.payload.hostKeyFingerprint)
        #expect(code.bootstrap?.seed == vector.payload.bootstrapSeed.flatMap(Base64URL.decode))
        #expect(code.bootstrap.map { Int($0.expiresAt.timeIntervalSince1970) } == vector.payload.expiresAt)
    }

    @Test("un code canonique se réencode à l'identique", arguments: PairingCodeVectors.shared.valid.filter { $0.decodeOnly != true })
    func roundTripsCanonicalVector(vector: PairingCodeVectors.Valid) throws {
        #expect(try PairingCode(parsing: vector.code).canonicalCode == vector.code)
    }

    @Test("un code invalide est refusé avec l'erreur attendue", arguments: PairingCodeVectors.shared.invalid)
    func rejectsInvalidVector(vector: PairingCodeVectors.Invalid) {
        #expect(throws: PairingCode.ParseError(rawValue: vector.error)!) {
            try PairingCode(parsing: vector.code)
        }
    }
}
