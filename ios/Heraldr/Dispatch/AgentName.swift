import Foundation

enum AgentName {
    enum Main: Equatable {
        case none
        case found(Agent)
        case ambiguous([String])
    }

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

    static func main(of workspace: Workspace, in agents: [Agent]) -> Main {
        let mains = agents.filter { $0.workspaceId == workspace.id && $0.name?.hasSuffix(suffix) == true }
        if mains.count == 1, let main = mains.first { return .found(main) }
        if mains.isEmpty { return .none }
        let named = forWorkspace(label: workspace.label)
        if let main = mains.first(where: { $0.name == named }) { return .found(main) }
        return .ambiguous(mains.compactMap(\.name))
    }
}
