import Foundation
import Speech

enum DictationLanguage: Equatable, Sendable {
    case iPhone
    case specific(String)

    func locale(preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        switch self {
        case .iPhone:
            preferredLanguages.first.map(Locale.init(identifier:)) ?? .current
        case .specific(let identifier):
            Locale(identifier: identifier)
        }
    }

    static func name(of locale: Locale) -> String {
        let identifier = locale.identifier(.bcp47)
        return Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
    }
}

enum DictationLanguageStore {
    private static let key = "dictation-language"

    static func load(from defaults: UserDefaults = .standard) -> DictationLanguage {
        defaults.string(forKey: key).map(DictationLanguage.specific) ?? .iPhone
    }

    static func save(_ language: DictationLanguage, to defaults: UserDefaults = .standard) {
        switch language {
        case .iPhone:
            defaults.removeObject(forKey: key)
        case .specific(let identifier):
            defaults.set(identifier, forKey: key)
        }
    }
}

enum TranscriptionLocales {
    static func supported() async -> [Locale] {
        var locales = await DictationTranscriber.supportedLocales
        if SpeechTranscriber.isAvailable {
            locales += await SpeechTranscriber.supportedLocales
        }
        return sortedByName(locales)
    }

    static func sortedByName(_ locales: [Locale]) -> [Locale] {
        var seen = Set<String>()
        let unique = locales.filter { seen.insert($0.identifier(.bcp47)).inserted }
        return unique.sorted { DictationLanguage.name(of: $0).localizedStandardCompare(DictationLanguage.name(of: $1)) == .orderedAscending }
    }
}
