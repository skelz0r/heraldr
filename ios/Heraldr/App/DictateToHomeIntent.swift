import AppIntents

struct DictateToHomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate to Home"
    static let description = IntentDescription("Opens the microphone to dictate a request to the main Claude of Home.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Dependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.dictateToHome()
        return .result()
    }
}

struct HeraldrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateToHomeIntent(),
            phrases: ["Dictate to Home with \(.applicationName)", "Dictate with \(.applicationName)"],
            shortTitle: "Dictate to Home",
            systemImageName: "mic.fill")
    }
}
