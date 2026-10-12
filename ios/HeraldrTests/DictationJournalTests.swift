import Foundation
import Testing

@testable import Heraldr

@MainActor
@Suite("Dictation journal sent to the Mac")
struct DictationJournalTests {
    private actor FakeMac {
        private(set) var received: [Data] = []
        var reachable = true

        func setReachable(_ reachable: Bool) {
            self.reachable = reachable
        }

        func append(_ entries: Data) throws {
            guard reachable else { throw MacLinkError.unreachable("offline") }
            received.append(entries)
        }

        nonisolated var mirror: DictationJournalMirror {
            DictationJournalMirror { try await self.append($0) }
        }

        var entries: [DictationJournalEntry] {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return received.reduce(Data(), +)
                .split(separator: UInt8(ascii: "\n"))
                .compactMap { try? decoder.decode(DictationJournalEntry.self, from: Data($0)) }
        }
    }

    private let fileURL = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID())/dictation-journal.jsonl")

    private func dictated(_ text: String) -> ComposeView.Origin {
        .dictated(DictatedText(.cleaned(text, raw: text)))
    }

    @Test(
        "a send dictated in two bursts keeps, for each one, the raw text, the text after replacement, the hints, the proposed text and what it became until the send"
    )
    func dictatedSendIsJournaled() async throws {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me"])
        lexicon.learn(sent: "Open the git hub of the project tonight.", origin: dictated("Open the guithub of the project tonight."))
        let first = await TranscriptCleaner.clean(
            "run ack me and the guithub", lexicon: lexicon, model: CleaningModel { _, _ in .text("Run Acme and the git hub.") })
        let second = await TranscriptCleaner.clean(
            "then open the PR", lexicon: lexicon, model: CleaningModel { _, _ in .failed(reason: "Apple Intelligence is turned off") })
        let edited = "Run Acme and the GitHub."
        let sent = "Run Acme and the GitHub.\nThen open the PR."
        let origin = ComposeView.Origin.dictated(DictatedText(first).appending(second, after: edited))
        let journal = DictationJournal(fileURL: fileURL)
        let mac = FakeMac()

        journal.record(sent: sent, origin: origin, at: Date(timeIntervalSince1970: 1_760_000_000))
        await journal.upload(with: mac.mirror)

        let entry = try #require(await mac.entries.first)
        #expect(entry.version == 1)
        #expect(entry.sent == sent)
        #expect(entry.sentAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(
            entry.salves == [
                DictationJournalEntry.Salve(
                    raw: "run ack me and the guithub",
                    replaced: "run Acme and the guithub",
                    replacements: [DictationLexicon.Replacement(heard: "ack me", term: "Acme")],
                    hints: [CleaningTrace.Hint(heard: "guithub", term: "git hub", applied: true)],
                    proposed: "Run Acme and the git hub.",
                    reason: nil,
                    previewed: "Run Acme and the git hub.",
                    edited: edited),
                DictationJournalEntry.Salve(
                    raw: "then open the PR",
                    replaced: "then open the PR",
                    replacements: [],
                    hints: [],
                    proposed: "then open the PR",
                    reason: "Apple Intelligence is turned off",
                    previewed: "Run Acme and the GitHub.\nthen open the PR",
                    edited: sent),
            ])
    }

    @Test("a hint the model did not follow is recorded as not applied")
    func ignoredHintIsNotApplied() async throws {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Open the git hub of the project tonight.", origin: dictated("Open the guithub of the project tonight."))
        let salve = await TranscriptCleaner.clean(
            "look at the guithub", lexicon: lexicon, model: CleaningModel { _, _ in .text("Look at the guithub.") })
        let journal = DictationJournal(fileURL: fileURL)
        let mac = FakeMac()

        journal.record(sent: "Look at the guithub.", origin: .dictated(DictatedText(salve)))
        await journal.upload(with: mac.mirror)

        let entry = try #require(await mac.entries.first)
        #expect(entry.salves.map(\.hints) == [[CleaningTrace.Hint(heard: "guithub", term: "git hub", applied: false)]])
    }

    @Test("the journal pending on the iPhone is left out of the iCloud backup")
    func pendingJournalIsExcludedFromBackup() throws {
        let journal = DictationJournal(fileURL: fileURL)

        journal.record(sent: "Run the tests.", origin: dictated("Run the tests."))

        #expect(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("a written or pasted send is not journaled")
    func writtenOrPastedSendIsNotJournaled() async {
        let journal = DictationJournal(fileURL: fileURL)
        let mac = FakeMac()

        journal.record(sent: "Typed by hand", origin: .written)
        journal.record(sent: "Pasted from the clipboard", origin: .pasted)
        await journal.upload(with: mac.mirror)

        #expect(await mac.received.isEmpty)
    }

    @Test("Mac unreachable: the journal is not lost, even after a relaunch, and goes out only once at the next connection")
    func journalWaitsForTheMac() async {
        let mac = FakeMac()
        await mac.setReachable(false)
        let journal = DictationJournal(fileURL: fileURL)

        journal.record(sent: "Run the tests.", origin: dictated("Run the tests."))
        await journal.upload(with: mac.mirror)
        journal.record(sent: "Then push.", origin: dictated("Then push."))
        await mac.setReachable(true)
        let relaunched = DictationJournal(fileURL: fileURL)
        await relaunched.upload(with: mac.mirror)
        await relaunched.upload(with: mac.mirror)

        #expect(await mac.entries.map(\.sent) == ["Run the tests.", "Then push."])
        #expect(await mac.received.count == 1)
    }
}
