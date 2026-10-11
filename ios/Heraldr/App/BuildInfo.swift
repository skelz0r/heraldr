import Foundation

struct BuildInfo {
    let version: String
    let commit: String?
    let builtAt: Date?

    static let current = BuildInfo(bundle: .main)

    init(bundle: Bundle) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        commit = (bundle.object(forInfoDictionaryKey: "HeraldrBuildCommit") as? String).flatMap { $0.isEmpty ? nil : $0 }
        builtAt = (bundle.object(forInfoDictionaryKey: "HeraldrBuildDate") as? String).flatMap { try? Date($0, strategy: .iso8601) }
    }
}
