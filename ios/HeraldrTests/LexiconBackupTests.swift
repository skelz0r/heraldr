import Foundation
import Testing

@testable import Heraldr

@MainActor
@Suite("Lexicon backup on the Mac")
struct LexiconBackupTests {
    private actor FakeMac {
        var file: Data?
        var readable = true
        private(set) var reads = 0
        private(set) var writes = 0

        init(file: Data? = nil) {
            self.file = file
        }

        func setReadable(_ readable: Bool) {
            self.readable = readable
        }

        func read() throws -> Data {
            guard readable else { throw MacLinkError.commandFailed(status: 1, stderr: "read failed") }
            reads += 1
            return file ?? Data()
        }

        func write(_ data: Data) {
            writes += 1
            file = data
        }

        nonisolated var mirror: LexiconMirror {
            LexiconMirror(fetch: { try await self.read() }, store: { await self.write($0) })
        }
    }

    private let store: DictationLexiconStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "lexicon-\(UUID())")
        let defaults = try #require(UserDefaults(suiteName: "lexicon-backup-\(UUID())"))
        store = DictationLexiconStore(fileURL: directory.appending(path: "dictation-lexicon.json"), defaults: defaults)
    }

    private func lexicon(_ terms: [(String, [String])]) -> DictationLexicon {
        var lexicon = DictationLexicon()
        for (offset, term) in terms.enumerated().reversed() {
            lexicon.define(term.0, heard: term.1, at: Date(timeIntervalSince1970: 1_760_000_000 + Double(offset)))
        }
        return lexicon
    }

    private func texts(_ lexicon: DictationLexicon) -> [String] {
        lexicon.terms.map(\.text)
    }

    @Test("after a new pairing with an empty local lexicon, the Mac lexicon is restored and survives a relaunch")
    func emptyLexiconIsRestoredAfterPairing() async {
        let backup = lexicon([("Acme", ["ack me"]), ("herdr", ["her door"])])
        let mac = FakeMac(file: backup.json)
        let keeper = LexiconKeeper(store: store)

        keeper.paired()
        let restored = await keeper.sync(with: mac.mirror)

        #expect(restored == 2)
        #expect(keeper.lexicon == backup)
        #expect(LexiconKeeper(store: store).lexicon == backup)
    }

    @Test("after a new pairing with a non-empty local lexicon, the Mac is not read and its backup is overwritten")
    func localLexiconOverwritesMacAfterPairing() async {
        let local = lexicon([("Acme", ["ack me"])])
        let mac = FakeMac(file: lexicon([("herdr", ["her door"])]).json)
        store.save(local)
        let keeper = LexiconKeeper(store: store)

        keeper.paired()
        let restored = await keeper.sync(with: mac.mirror)

        #expect(restored == nil)
        #expect(await mac.reads == 0)
        #expect(await mac.file == local.json)
        #expect(keeper.lexicon == local)
    }

    @Test(
        "Mac unreadable during the restore: its backup is not overwritten, it is restored at the next connection along with what was learned in the meantime"
    )
    func restoreIsRetriedWithoutOverwritingMac() async {
        let backup = lexicon([("Acme", ["ack me"])])
        let mac = FakeMac(file: backup.json)
        await mac.setReadable(false)
        let keeper = LexiconKeeper(store: store)

        keeper.paired()
        await keeper.sync(with: mac.mirror)
        keeper.update(lexicon([("git push", ["on push"])]))
        await keeper.sync(with: mac.mirror)
        #expect(await mac.writes == 0)
        await mac.setReadable(true)
        let relaunched = LexiconKeeper(store: store)
        let restored = await relaunched.sync(with: mac.mirror)

        #expect(restored == 1)
        #expect(texts(relaunched.lexicon) == ["git push", "Acme"])
        #expect(await mac.file == relaunched.lexicon.json)
    }

    @Test("a lexicon change is backed up once on the Mac, not at every connection")
    func changeIsBackedUpOnce() async {
        let mac = FakeMac()
        let keeper = LexiconKeeper(store: store)
        await keeper.sync(with: mac.mirror)
        let writesBefore = await mac.writes

        let now = Date(timeIntervalSince1970: 1_760_000_500)

        keeper.update(lexicon([("Acme", ["ack me"])]))
        await keeper.sync(with: mac.mirror, now: now)
        await keeper.sync(with: mac.mirror, now: now.addingTimeInterval(60))

        #expect(await mac.writes == writesBefore + 1)
        #expect(await mac.file == keeper.lexicon.json)
        #expect(keeper.backupState == .savedOnMac(now))
    }
}
