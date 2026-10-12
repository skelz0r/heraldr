import Foundation

struct PairingCode: Equatable, Sendable {
    let addresses: [String]
    let port: Int
    let username: String
    let hostKeyFingerprint: String
    let bootstrap: Bootstrap?

    struct Bootstrap: Equatable, Sendable {
        let seed: Data
        let expiresAt: Date
    }

    enum ParseError: String, Error, Equatable {
        case badPrefix = "bad_prefix"
        case unsupportedVersion = "unsupported_version"
        case badEncoding = "bad_encoding"
        case badPayload = "bad_payload"
    }

    static let prefix = "HERDR-PAIR"
    static let supportedVersion = 1

    init(addresses: [String], port: Int, username: String, hostKeyFingerprint: String, bootstrap: Bootstrap?) {
        self.addresses = addresses
        self.port = port
        self.username = username
        self.hostKeyFingerprint = hostKeyFingerprint
        self.bootstrap = bootstrap
    }

    init(parsing code: String) throws(ParseError) {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == Self.prefix else { throw .badPrefix }
        guard parts[1].allSatisfy(\.isASCII), parts[1].allSatisfy(\.isNumber), Int(parts[1]) == Self.supportedVersion else {
            throw .unsupportedVersion
        }
        guard
            let body = Base64URL.decode(String(parts[2])),
            let json = try? JSONSerialization.jsonObject(with: body),
            let payload = json as? [String: Any]
        else { throw .badEncoding }
        self = try Self.validated(payload)
    }

    var canonicalCode: String {
        var fields = [
            "\"addrs\":[" + addresses.map(Self.jsonString).joined(separator: ",") + "]",
            "\"port\":\(port)",
            "\"user\":" + Self.jsonString(username),
            "\"fp\":" + Self.jsonString(hostKeyFingerprint),
        ]
        if let bootstrap {
            fields.append("\"seed\":" + Self.jsonString(Base64URL.encode(bootstrap.seed)))
            fields.append("\"exp\":\(Int(bootstrap.expiresAt.timeIntervalSince1970))")
        }
        let body = Data(("{" + fields.joined(separator: ",") + "}").utf8)
        return "\(Self.prefix):\(Self.supportedVersion):\(Base64URL.encode(body))"
    }

    private static func validated(_ payload: [String: Any]) throws(ParseError) -> PairingCode {
        guard
            let addresses = payload["addrs"] as? [String],
            !addresses.isEmpty,
            addresses.allSatisfy(isNonEmptyWithoutWhitespace),
            let port = integer(payload["port"]),
            (1...65_535).contains(port),
            let username = payload["user"] as? String,
            isNonEmptyWithoutWhitespace(username),
            let fingerprint = payload["fp"] as? String,
            isOpenSSHFingerprint(fingerprint)
        else { throw .badPayload }

        let bootstrap: Bootstrap?
        switch (payload["seed"], payload["exp"]) {
        case (nil, nil):
            bootstrap = nil
        case (let seedValue?, let expiryValue?):
            guard
                let seedText = seedValue as? String,
                let seed = Base64URL.decode(seedText),
                seed.count == 32,
                let expiry = integer(expiryValue)
            else { throw .badPayload }
            bootstrap = Bootstrap(seed: seed, expiresAt: Date(timeIntervalSince1970: TimeInterval(expiry)))
        default:
            throw .badPayload
        }

        return PairingCode(
            addresses: addresses,
            port: port,
            username: username,
            hostKeyFingerprint: fingerprint,
            bootstrap: bootstrap)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 9_007_199_254_740_992 else { return nil }
        return number.intValue
    }

    private static func isNonEmptyWithoutWhitespace(_ text: String) -> Bool {
        !text.isEmpty && !text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isOpenSSHFingerprint(_ text: String) -> Bool {
        text.wholeMatch(of: #/SHA256:[A-Za-z0-9+\/]{43}/#) != nil
    }

    private static func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = (try? encoder.encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

enum Base64URL {
    static func decode(_ text: String) -> Data? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: standard)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: ["="])
    }
}
