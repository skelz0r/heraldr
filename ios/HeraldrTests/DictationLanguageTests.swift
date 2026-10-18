import Foundation
import Testing

@testable import Heraldr

@MainActor
@Suite("Dictation language")
struct DictationLanguageTests {
    @Test("by default, the microphone listens in the iPhone's first preferred language, not in the app's English")
    func followsTheIPhoneLanguage() {
        let locale = DictationLanguage.iPhone.locale(preferredLanguages: ["fr-FR", "en-US"])
        #expect(locale.identifier(.bcp47) == "fr-FR")
    }

    @Test("a language chosen in Settings is kept at the next launch, and going back to the iPhone language forgets it")
    func chosenLanguageIsKept() {
        let suite = "heraldr-tests-\(UUID().uuidString)"
        let scenario = FakeMacScenario()
        let model = AppModel(environment: .fake(scenario, suiteName: suite))
        #expect(model.dictationLanguage == .iPhone)

        model.dictationLanguage = .specific("fr-CA")
        let relaunched = AppModel(environment: .fake(scenario, suiteName: suite, relaunching: true))
        #expect(relaunched.dictationLanguage == .specific("fr-CA"))
        #expect(relaunched.dictationLanguage.locale().identifier(.bcp47) == "fr-CA")

        relaunched.dictationLanguage = .iPhone
        #expect(AppModel(environment: .fake(scenario, suiteName: suite, relaunching: true)).dictationLanguage == .iPhone)
    }
}
