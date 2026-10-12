import Foundation

struct DictationJournalEntry: Codable, Equatable, Sendable {
    struct Salve: Codable, Equatable, Sendable {
        let raw: String
        let replaced: String
        let replacements: [DictationLexicon.Replacement]
        let hints: [CleaningTrace.Hint]
        let proposed: String
        let reason: String?
        let previewed: String
        let edited: String
    }

    static let formatVersion = 1

    let version: Int
    let id: String
    let sentAt: Date
    let sent: String
    let salves: [Salve]

    init?(sent: String, origin: ComposeView.Origin, id: UUID = UUID(), at date: Date = .now) {
        guard case .dictated(let dictated) = origin else { return nil }
        version = Self.formatVersion
        self.id = id.uuidString
        sentAt = date
        self.sent = sent
        salves = zip(dictated.salves, dictated.revisions(sentAs: sent)).map { salve, revision in
            let trace = salve.trace
            return Salve(
                raw: salve.raw,
                replaced: trace?.replaced ?? salve.raw,
                replacements: trace?.replacements ?? [],
                hints: trace?.hints ?? [],
                proposed: salve.text,
                reason: salve.reason,
                previewed: revision.proposed,
                edited: revision.edited)
        }
    }

    var jsonLine: Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(self)) ?? Data()) + Data("\n".utf8)
    }
}

struct DictationJournalMirror: Sendable {
    let append: @Sendable (Data) async throws -> Void
}

@MainActor
final class DictationJournal {
    static let pendingCapacity = 500

    private let fileURL: URL
    private var uploading = false
    private var uploadRequestedWhileUploading = false

    init(fileURL: URL = .applicationSupportDirectory.appending(path: "dictation-journal.jsonl")) {
        self.fileURL = fileURL
    }

    func record(sent: String, origin: ComposeView.Origin, at date: Date = .now) {
        guard let entry = DictationJournalEntry(sent: sent, origin: origin, at: date) else { return }
        let lines = Array((pendingLines + [entry.jsonLine]).suffix(Self.pendingCapacity))
        write(lines)
    }

    func upload(with mirror: DictationJournalMirror) async {
        guard !uploading else {
            uploadRequestedWhileUploading = true
            return
        }
        uploading = true
        defer { uploading = false }
        repeat {
            uploadRequestedWhileUploading = false
            let batch = pendingLines
            guard !batch.isEmpty, (try? await mirror.append(batch.reduce(Data(), +))) != nil else { return }
            write(pendingLines.filter { !batch.contains($0) })
        } while uploadRequestedWhileUploading
    }

    private var pendingLines: [Data] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).map { Data($0) + Data("\n".utf8) }
    }

    private func write(_ lines: [Data]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.reduce(Data(), +).write(to: fileURL, options: .atomic)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var url = fileURL
        try? url.setResourceValues(excluded)
    }
}
