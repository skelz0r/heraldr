import Foundation

struct DictationCorrection: Codable, Equatable, Sendable, Identifiable {
    let heard: String
    var meant: String
    var count: Int
    var learnedAt: Date

    var id: String { heard }
}

struct DictationLexicon: Codable, Equatable, Sendable {
    static let capacity = 50
    static let maxWordsPerSide = 3
    static let maxChangedShare = 0.5
    static let promptedCorrections = 20

    private(set) var corrections: [DictationCorrection] = []

    var vocabulary: [String] {
        corrections.map(\.meant)
    }

    var promptLines: [String] {
        corrections.prefix(Self.promptedCorrections).map { "\($0.heard) → \($0.meant)" }
    }

    mutating func learn(sent: String, origin: ComposeView.Origin, at date: Date = .now) {
        guard case .dictated(let dictated) = origin else { return }
        for revision in dictated.revisions(sentAs: sent) {
            for (heard, meant) in Self.substitutions(from: revision.proposed, to: revision.edited) {
                remember(heard: heard, meant: meant, at: date)
            }
        }
    }

    static func normalized(heard: String, meant: String) -> (heard: String, meant: String)? {
        let heardWords = words(heard)
        let meantWords = words(meant)
        guard
            (1...maxWordsPerSide).contains(heardWords.count),
            (1...maxWordsPerSide).contains(meantWords.count),
            heardWords.map(key) != meantWords.map(key)
        else { return nil }
        return (heardWords.joined(separator: " "), meantWords.joined(separator: " "))
    }

    @discardableResult
    mutating func correct(heard: String, meant: String, replacing original: String? = nil, at date: Date = .now) -> Bool {
        guard let correction = Self.normalized(heard: heard, meant: meant) else { return false }
        if let original { forget(heard: original) }
        remember(heard: correction.heard, meant: correction.meant, at: date)
        return true
    }

    mutating func forget(heard: String) {
        corrections.removeAll { Self.key($0.heard) == Self.key(heard) }
    }

    private mutating func remember(heard: String, meant: String, at date: Date) {
        var correction = DictationCorrection(heard: heard, meant: meant, count: 1, learnedAt: date)
        if let index = corrections.firstIndex(where: { Self.key($0.heard) == Self.key(heard) }) {
            let known = corrections.remove(at: index)
            if Self.key(known.meant) == Self.key(meant) { correction.count = known.count + 1 }
        }
        corrections = Array(([correction] + corrections).prefix(Self.capacity))
    }

    static func substitutions(from proposed: String, to sent: String) -> [(heard: String, meant: String)] {
        let before = words(proposed)
        let after = words(sent)
        let hunks = changedHunks(before.map(key), after.map(key))
        let changed = hunks.reduce(0) { $0 + max($1.before.count, $1.after.count) }
        guard !before.isEmpty, Double(changed) <= Double(before.count) * maxChangedShare else { return [] }
        return hunks.compactMap { hunk in
            guard
                (1...maxWordsPerSide).contains(hunk.before.count),
                (1...maxWordsPerSide).contains(hunk.after.count)
            else { return nil }
            let (heard, meant) = hunk.before.count == 1 && hunk.after.count == 1
                ? withNeighbour(hunk, before: before.count) : hunk
            return (before[heard].joined(separator: " "), after[meant].joined(separator: " "))
        }
    }

    private static func withNeighbour(_ hunk: (before: Range<Int>, after: Range<Int>), before count: Int) -> (Range<Int>, Range<Int>) {
        if hunk.before.upperBound < count {
            return (hunk.before.lowerBound..<hunk.before.upperBound + 1, hunk.after.lowerBound..<hunk.after.upperBound + 1)
        }
        if hunk.before.lowerBound > 0 {
            return (hunk.before.lowerBound - 1..<hunk.before.upperBound, hunk.after.lowerBound - 1..<hunk.after.upperBound)
        }
        return (hunk.before, hunk.after)
    }

    private static let edgePunctuation = CharacterSet(charactersIn: ",;:.!?…«»\"“”()'’")

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
    }

    private static func key(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    private static func changedHunks(_ before: [String], _ after: [String]) -> [(before: Range<Int>, after: Range<Int>)] {
        var common = Array(repeating: Array(repeating: 0, count: after.count + 1), count: before.count + 1)
        for i in stride(from: before.count - 1, through: 0, by: -1) {
            for j in stride(from: after.count - 1, through: 0, by: -1) {
                common[i][j] = before[i] == after[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
            }
        }
        var hunks: [(before: Range<Int>, after: Range<Int>)] = []
        var i = 0
        var j = 0
        var start = (0, 0)
        func close() {
            if start.0 < i || start.1 < j { hunks.append((start.0..<i, start.1..<j)) }
        }
        while i < before.count || j < after.count {
            if i < before.count, j < after.count, before[i] == after[j] {
                close()
                i += 1
                j += 1
                start = (i, j)
            } else if j < after.count, i == before.count || common[i][j + 1] >= common[i + 1][j] {
                j += 1
            } else {
                i += 1
            }
        }
        close()
        return hunks
    }
}

enum DictationLexiconStore {
    private static let key = "dictation-lexicon"

    static func load(from defaults: UserDefaults = .standard) -> DictationLexicon {
        guard
            let data = defaults.data(forKey: key),
            let lexicon = try? JSONDecoder().decode(DictationLexicon.self, from: data)
        else { return DictationLexicon() }
        return lexicon
    }

    static func save(_ lexicon: DictationLexicon, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(lexicon), forKey: key)
    }
}
