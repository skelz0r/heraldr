import Foundation

enum AgentName {
    static let suffix = "-main"
    static let maximumSlugLength = 27
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-".unicodeScalars)
    private static let letters = Set("abcdefghijklmnopqrstuvwxyz".unicodeScalars)
    private static let uppercase: ClosedRange<Unicode.Scalar> = "A"..."Z"

    static func forWorkspace(label: String) -> String {
        slug(label) + suffix
    }

    static func slug(_ label: String) -> String {
        guard label != Workspace.homeLabel else { return "home" }
        var slug = String(String.UnicodeScalarView(label.unicodeScalars.map(slugScalar)))
        if slug.unicodeScalars.first.map({ !letters.contains($0) }) ?? true {
            slug = "w-" + slug
        }
        return String(slug.prefix(maximumSlugLength))
    }

    private static func slugScalar(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        let lowered = uppercase.contains(scalar) ? Unicode.Scalar(scalar.value + 32) ?? scalar : scalar
        return allowed.contains(lowered) ? lowered : "-"
    }
}
