struct DictatedText: Equatable, Sendable {
    struct Revision: Equatable, Sendable {
        let proposed: String
        let edited: String
    }

    private(set) var salves: [CleanedTranscript]
    private var closedRevisions: [Revision]
    private var proposed: String

    init(_ salve: CleanedTranscript, after existing: String = "") {
        salves = [salve]
        closedRevisions = []
        proposed = Self.append(salve, to: existing)
    }

    var text: String { proposed }

    func appending(_ salve: CleanedTranscript, after edited: String) -> DictatedText {
        var next = self
        next.salves.append(salve)
        next.closedRevisions.append(Revision(proposed: proposed, edited: edited))
        next.proposed = Self.append(salve, to: edited)
        return next
    }

    func revisions(sentAs sent: String) -> [Revision] {
        closedRevisions + [Revision(proposed: proposed, edited: sent)]
    }

    private static func append(_ salve: CleanedTranscript, to existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? salve.text : trimmed + "\n" + salve.text
    }
}
