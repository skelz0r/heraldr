import Foundation

struct PairedMac: Codable, Equatable, Sendable {
    var addresses: [String]
    let port: Int
    let username: String
    let hostKeyFingerprint: String

    func preferring(_ address: String) -> PairedMac {
        var copy = self
        copy.addresses = [address] + addresses.filter { $0 != address }
        return copy
    }
}

enum PairedMacStore {
    private static let key = "paired-mac"

    static func load(from defaults: UserDefaults = .standard) -> PairedMac? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PairedMac.self, from: data)
    }

    static func save(_ mac: PairedMac, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(mac), forKey: key)
    }

    static func forget(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
