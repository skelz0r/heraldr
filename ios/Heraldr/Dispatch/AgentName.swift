import Foundation

enum AgentName {
    static let suffix = "-main"
    static let maximumSlugLength = 27
    private static let kept = Set("abcdefghijklmnopqrstuvwxyz0123456789_- ")
    private static let letters = Set("abcdefghijklmnopqrstuvwxyz")

    static func forWorkspace(label: String) -> String {
        slug(label) + suffix
    }

    static func slug(_ label: String) -> String {
        guard label != Workspace.homeLabel else { return "home" }
        let ascii = String(String.UnicodeScalarView(label.decomposedStringWithCanonicalMapping.unicodeScalars.filter(\.isASCII)))
        var slug = ascii.lowercased().filter(kept.contains)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        if slug.first.map({ !letters.contains($0) }) ?? true {
            slug = "w-" + slug
        }
        return String(slug.prefix(maximumSlugLength))
    }
}
