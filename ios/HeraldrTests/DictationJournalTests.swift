import Foundation
import Testing

@testable import Heraldr

@MainActor
@Suite("Journal des dictées envoyé au Mac")
struct DictationJournalTests {
    private actor FakeMac {
        private(set) var received: [Data] = []
        var reachable = true

        func setReachable(_ reachable: Bool) {
            self.reachable = reachable
        }

        func append(_ entries: Data) throws {
            guard reachable else { throw MacLinkError.unreachable("hors ligne") }
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
        "un envoi dicté en deux salves garde, pour chacune, le brut, le texte après remplacement, les indices, le texte proposé et ce qu'il est devenu jusqu'à l'envoi"
    )
    func dictatedSendIsJournaled() async throws {
        var lexicon = DictationLexicon()
        lexicon.define("Acme", heard: ["ack me"])
        lexicon.learn(sent: "Ouvre le git hub du projet ce soir.", origin: dictated("Ouvre le guithub du projet ce soir."))
        let first = await TranscriptCleaner.clean(
            "lance ack me et le guithub", lexicon: lexicon, model: CleaningModel { _, _ in .text("Lance Acme et le git hub.") })
        let second = await TranscriptCleaner.clean(
            "puis ouvre la PR", lexicon: lexicon, model: CleaningModel { _, _ in .failed(reason: "Apple Intelligence est désactivé") })
        let edited = "Lance Acme et le GitHub."
        let sent = "Lance Acme et le GitHub.\nPuis ouvre la PR."
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
                    raw: "lance ack me et le guithub",
                    replaced: "lance Acme et le guithub",
                    replacements: [DictationLexicon.Replacement(heard: "ack me", term: "Acme")],
                    hints: [CleaningTrace.Hint(heard: "guithub", term: "git hub", applied: true)],
                    proposed: "Lance Acme et le git hub.",
                    reason: nil,
                    previewed: "Lance Acme et le git hub.",
                    edited: edited),
                DictationJournalEntry.Salve(
                    raw: "puis ouvre la PR",
                    replaced: "puis ouvre la PR",
                    replacements: [],
                    hints: [],
                    proposed: "puis ouvre la PR",
                    reason: "Apple Intelligence est désactivé",
                    previewed: "Lance Acme et le GitHub.\npuis ouvre la PR",
                    edited: sent),
            ])
    }

    @Test("un indice que le modèle n'a pas suivi est noté non appliqué")
    func ignoredHintIsNotApplied() async throws {
        var lexicon = DictationLexicon()
        lexicon.learn(sent: "Ouvre le git hub du projet ce soir.", origin: dictated("Ouvre le guithub du projet ce soir."))
        let salve = await TranscriptCleaner.clean(
            "regarde le guithub", lexicon: lexicon, model: CleaningModel { _, _ in .text("Regarde le guithub.") })
        let journal = DictationJournal(fileURL: fileURL)
        let mac = FakeMac()

        journal.record(sent: "Regarde le guithub.", origin: .dictated(DictatedText(salve)))
        await journal.upload(with: mac.mirror)

        let entry = try #require(await mac.entries.first)
        #expect(entry.salves.map(\.hints) == [[CleaningTrace.Hint(heard: "guithub", term: "git hub", applied: false)]])
    }

    @Test("le journal en attente sur l'iPhone n'entre pas dans la sauvegarde iCloud")
    func pendingJournalIsExcludedFromBackup() throws {
        let journal = DictationJournal(fileURL: fileURL)

        journal.record(sent: "Lance les tests.", origin: dictated("Lance les tests."))

        #expect(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test("un envoi écrit ou collé n'entre pas au journal")
    func writtenOrPastedSendIsNotJournaled() async {
        let journal = DictationJournal(fileURL: fileURL)
        let mac = FakeMac()

        journal.record(sent: "Écrit à la main", origin: .written)
        journal.record(sent: "Collé du presse-papiers", origin: .pasted)
        await journal.upload(with: mac.mirror)

        #expect(await mac.received.isEmpty)
    }

    @Test("Mac injoignable : le journal n'est pas perdu, même après une relance, et part une seule fois à la connexion suivante")
    func journalWaitsForTheMac() async {
        let mac = FakeMac()
        await mac.setReachable(false)
        let journal = DictationJournal(fileURL: fileURL)

        journal.record(sent: "Lance les tests.", origin: dictated("Lance les tests."))
        await journal.upload(with: mac.mirror)
        journal.record(sent: "Puis pousse.", origin: dictated("Puis pousse."))
        await mac.setReachable(true)
        let relaunched = DictationJournal(fileURL: fileURL)
        await relaunched.upload(with: mac.mirror)
        await relaunched.upload(with: mac.mirror)

        #expect(await mac.entries.map(\.sent) == ["Lance les tests.", "Puis pousse."])
        #expect(await mac.received.count == 1)
    }
}
