import Foundation

struct DictationVariant: Codable, Equatable, Sendable {
    var heard: String
    var source: DictationLexicon.Source
    var count: Int
    var updatedAt: Date
}

struct DictationTerm: Codable, Equatable, Sendable, Identifiable {
    var text: String
    var source: DictationLexicon.Source
    var variants: [DictationVariant]
    var updatedAt: Date

    var id: String { DictationLexicon.key(text) }
}

struct DictationLexicon: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case typed
        case learned

        init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .learned
        }
    }

    static let formatVersion = 1
    static let capacity = 200
    static let vocabularySize = 100
    static let maxWords = 3
    static let maxChangedShare = 0.5

    private(set) var terms: [DictationTerm] = []

    init() {}

    var vocabulary: [String] {
        terms.prefix(Self.vocabularySize).map(\.text)
    }

    var promptLines: [String] {
        terms.flatMap { term in term.variants.map { "\($0.heard) → \(term.text)" } }.prefix(20).map(\.self)
    }

    mutating func learn(sent: String, origin: ComposeView.Origin, at date: Date = .now) {
        guard case .dictated(let dictated) = origin else { return }
        for revision in dictated.revisions(sentAs: sent) {
            for (heard, meant) in Self.substitutions(from: revision.proposed, to: revision.edited) {
                remember(heard: heard, as: meant, at: date)
            }
        }
    }

    static func validated(_ text: String, heard: [String]) -> (text: String, heard: [String])? {
        guard let term = normalized(text) else { return nil }
        var keys: Set<String> = [key(term)]
        var variants: [String] = []
        for candidate in heard where !words(candidate).isEmpty {
            guard let variant = normalized(candidate), keys.insert(key(variant)).inserted else { return nil }
            variants.append(variant)
        }
        return (term, variants)
    }

    @discardableResult
    mutating func define(_ text: String, heard: [String], replacing original: DictationTerm.ID? = nil, at date: Date = .now) -> Bool {
        guard let definition = Self.validated(text, heard: heard) else { return false }
        let previous = terms.first { $0.id == original }
        let merged = terms.first { $0.id == Self.key(definition.text) && $0.id != original }
        let known = (previous?.variants ?? []) + (merged?.variants ?? [])
        var variants = definition.heard.map { heard in
            if var kept = known.first(where: { Self.key($0.heard) == Self.key(heard) }) {
                if kept.heard != heard { kept.source = .typed }
                kept.heard = heard
                return kept
            }
            return DictationVariant(heard: heard, source: .typed, count: 0, updatedAt: date)
        }
        if let merged {
            variants += merged.variants.filter { variant in !variants.contains { Self.key($0.heard) == Self.key(variant.heard) } }
        }
        let source = previous?.text == definition.text && !variants.isEmpty ? previous?.source ?? .typed : .typed
        terms.removeAll { $0.id == original || $0.id == merged?.id }
        place(DictationTerm(text: definition.text, source: source, variants: variants, updatedAt: date))
        return true
    }

    mutating func forget(_ id: DictationTerm.ID) {
        terms.removeAll { $0.id == id }
    }

    private mutating func remember(heard: String, as meant: String, at date: Date) {
        var variant = DictationVariant(heard: heard, source: .learned, count: 1, updatedAt: date)
        if let known = terms.first(where: { $0.id == Self.key(meant) })?.variants.first(where: { Self.key($0.heard) == Self.key(heard) }) {
            variant.count = known.count + 1
            variant.source = known.source
        }
        let term = terms.first { $0.id == Self.key(meant) }
            ?? DictationTerm(text: meant, source: .learned, variants: [], updatedAt: date)
        let others = term.variants.filter { Self.key($0.heard) != Self.key(heard) }
        place(DictationTerm(text: term.text, source: term.source, variants: [variant] + others, updatedAt: date))
    }

    private mutating func place(_ term: DictationTerm) {
        let claimed = Set(term.variants.map { Self.key($0.heard) })
        terms = [term] + terms.compactMap { other in
            guard other.id != term.id else { return nil }
            var kept = other
            kept.variants.removeAll { claimed.contains(Self.key($0.heard)) }
            return kept.variants.isEmpty && kept.source == .learned ? nil : kept
        }
        terms = Array(terms.prefix(Self.capacity))
    }

    static func substitutions(from proposed: String, to sent: String) -> [(heard: String, meant: String)] {
        let before = words(proposed)
        let after = words(sent)
        let hunks = changedHunks(before.map(key), after.map(key))
        let changed = hunks.reduce(0) { $0 + max($1.before.count, $1.after.count) }
        guard !before.isEmpty, Double(changed) <= Double(before.count) * maxChangedShare else { return [] }
        return hunks.compactMap { hunk in
            guard
                (1...maxWords).contains(hunk.before.count),
                (1...maxWords).contains(hunk.after.count)
            else { return nil }
            let (heard, meant) = hunk.before.count == 1 && hunk.after.count == 1
                ? withNeighbour(hunk, before: before.count) : hunk
            return (before[heard].joined(separator: " "), after[meant].joined(separator: " "))
        }
    }

    private static func normalized(_ text: String) -> String? {
        let words = words(text)
        guard (1...maxWords).contains(words.count) else { return nil }
        return words.joined(separator: " ")
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

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
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

extension DictationLexicon {
    private enum CodingKeys: String, CodingKey {
        case version
        case terms
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version <= Self.formatVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "format \(version) inconnu")
        }
        terms = try container.decode([DictationTerm].self, forKey: .terms)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(terms, forKey: .terms)
    }

    init?(json: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let lexicon = try? decoder.decode(Self.self, from: json) else { return nil }
        self = lexicon
    }

    var json: Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }

    fileprivate init(migrating corrections: [LegacyCorrection]) {
        for correction in corrections {
            let variant = DictationVariant(heard: correction.heard, source: .learned, count: correction.count, updatedAt: correction.learnedAt)
            if let index = terms.firstIndex(where: { $0.id == Self.key(correction.meant) }) {
                terms[index].variants.append(variant)
            } else {
                terms.append(DictationTerm(text: correction.meant, source: .learned, variants: [variant], updatedAt: correction.learnedAt))
            }
        }
    }
}

private struct LegacyCorrection: Decodable {
    let heard: String
    let meant: String
    let count: Int
    let learnedAt: Date
}

private struct LegacyLexicon: Decodable {
    let corrections: [LegacyCorrection]
}

struct DictationLexiconStore {
    private static let legacyKey = "dictation-lexicon"

    let fileURL: URL
    let defaults: UserDefaults

    static var standard: DictationLexiconStore {
        DictationLexiconStore(fileURL: .applicationSupportDirectory.appending(path: "dictation-lexicon.json"), defaults: .standard)
    }

    func load() -> DictationLexicon {
        if let data = try? Data(contentsOf: fileURL), let lexicon = DictationLexicon(json: data) {
            return lexicon
        }
        guard
            let data = defaults.data(forKey: Self.legacyKey),
            let legacy = try? JSONDecoder().decode(LegacyLexicon.self, from: data)
        else { return DictationLexicon() }
        let lexicon = DictationLexicon(migrating: legacy.corrections)
        if save(lexicon) { defaults.removeObject(forKey: Self.legacyKey) }
        return lexicon
    }

    @discardableResult
    func save(_ lexicon: DictationLexicon) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lexicon.json.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
