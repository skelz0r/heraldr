import CryptoKit
import Foundation
import Security

struct DeviceKey: Sendable {
    let privateKey: Curve25519.Signing.PrivateKey

    var publicKeyBlob: Data {
        var blob = Data()
        blob.appendSSHString(Data("ssh-ed25519".utf8))
        blob.appendSSHString(privateKey.publicKey.rawRepresentation)
        return blob
    }

    var fingerprint: String {
        SSHFingerprint.of(publicKeyBlob: publicKeyBlob)
    }

    func authorizedKeysLine(comment: String) -> String {
        "ssh-ed25519 " + publicKeyBlob.base64EncodedString() + " " + comment
    }

    func sign(_ challenge: Data) throws -> Data {
        try privateKey.signature(for: challenge)
    }
}

enum SSHFingerprint {
    static func of(publicKeyBlob: Data) -> String {
        "SHA256:" + Data(SHA256.hash(data: publicKeyBlob)).base64EncodedString().trimmingCharacters(in: ["="])
    }
}

enum DeviceKeyStore {
    private static let service = "com.skelz0r.heraldr.device-key"
    private static let account = "ed25519"

    enum StoreError: Error {
        case keychain(OSStatus)
    }

    static func loadOrCreate() throws -> DeviceKey {
        if let existing = try load() {
            return existing
        }
        let key = DeviceKey(privateKey: Curve25519.Signing.PrivateKey())
        try save(key)
        return key
    }

    static func load() throws -> DeviceKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw StoreError.keychain(status) }
        return DeviceKey(privateKey: try Curve25519.Signing.PrivateKey(rawRepresentation: data))
    }

    private static func save(_ key: DeviceKey) throws {
        var attributes = baseQuery
        attributes[kSecValueData as String] = key.privateKey.rawRepresentation
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

private extension Data {
    mutating func appendSSHString(_ bytes: Data) {
        var length = UInt32(bytes.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { append(contentsOf: $0) }
        append(bytes)
    }
}
