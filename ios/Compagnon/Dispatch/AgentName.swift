import Foundation

enum AgentName {
    static let suffix = "-main"
    static let maximumSlugLength = 27
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
    private static let letters = Set("abcdefghijklmnopqrstuvwxyz")

    static func forWorkspace(label: String) -> String {
        slug(label) + suffix
    }

    static func slug(_ label: String) -> String {
        guard label != Workspace.homeLabel else { return "home" }
        var slug = String(label.lowercased().map { allowed.contains($0) ? $0 : "-" })
        if slug.first.map({ !letters.contains($0) }) ?? true {
            slug = "w-" + slug
        }
        return String(slug.prefix(maximumSlugLength))
    }
}
