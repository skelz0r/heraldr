import Foundation
import Observation

struct LexiconMirror: Sendable {
    let fetch: @Sendable () async throws -> Data
    let store: @Sendable (Data) async throws -> Void
}

@MainActor
@Observable
final class LexiconKeeper {
    enum BackupState: Equatable {
        case restorePending
        case changesPending
        case savedOnMac(Date)
    }

    private enum Key {
        static let restorePending = "lexicon-restore-pending"
        static let backupNeeded = "lexicon-backup-needed"
        static let backedUpAt = "lexicon-backed-up-at"
    }

    private let store: DictationLexiconStore
    private(set) var lexicon: DictationLexicon
    private var syncing = false
    private var syncRequestedWhileSyncing = false

    private var restorePending: Bool {
        didSet { store.defaults.set(restorePending, forKey: Key.restorePending) }
    }

    private var backupNeeded: Bool {
        didSet { store.defaults.set(backupNeeded, forKey: Key.backupNeeded) }
    }

    private var backedUpAt: Date? {
        didSet { store.defaults.set(backedUpAt, forKey: Key.backedUpAt) }
    }

    init(store: DictationLexiconStore = .standard) {
        self.store = store
        lexicon = store.load()
        restorePending = store.defaults.bool(forKey: Key.restorePending)
        backupNeeded = store.defaults.object(forKey: Key.backupNeeded) as? Bool ?? true
        backedUpAt = store.defaults.object(forKey: Key.backedUpAt) as? Date
    }

    var backupState: BackupState {
        if restorePending { return .restorePending }
        guard !backupNeeded, let backedUpAt else { return .changesPending }
        return .savedOnMac(backedUpAt)
    }

    func update(_ lexicon: DictationLexicon) {
        guard lexicon != self.lexicon else { return }
        self.lexicon = lexicon
        store.save(lexicon)
        backupNeeded = true
    }

    func paired() {
        if lexicon.terms.isEmpty {
            restorePending = true
        } else {
            backupNeeded = true
        }
    }

    @discardableResult
    func sync(with mirror: LexiconMirror, now: Date = .now) async -> Int? {
        guard !syncing else {
            syncRequestedWhileSyncing = true
            return nil
        }
        syncing = true
        defer { syncing = false }
        var restored: Int?
        repeat {
            syncRequestedWhileSyncing = false
            restored = await syncOnce(with: mirror, now: now) ?? restored
        } while syncRequestedWhileSyncing
        return restored
    }

    private func syncOnce(with mirror: LexiconMirror, now: Date) async -> Int? {
        var restored: Int?
        if restorePending {
            guard let data = try? await mirror.fetch() else { return nil }
            if let backup = DictationLexicon(json: data), !backup.terms.isEmpty {
                let merged = lexicon.restoring(from: backup)
                guard store.save(merged) else { return nil }
                lexicon = merged
                restored = backup.terms.count
            }
            restorePending = false
        }
        guard backupNeeded else { return restored }
        let snapshot = lexicon
        guard (try? await mirror.store(snapshot.json)) != nil else { return restored }
        backedUpAt = now
        if lexicon == snapshot { backupNeeded = false }
        return restored
    }
}
