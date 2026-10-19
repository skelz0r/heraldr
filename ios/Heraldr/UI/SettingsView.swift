import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    private let build = BuildInfo.current

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Dictation") {
                    NavigationLink {
                        DictationLanguageView(language: $model.dictationLanguage, supportedLocales: model.transcriptionLocales)
                    } label: {
                        LabeledContent("Language", value: languageLabel)
                    }
                    .accessibilityIdentifier("settings.dictationLanguage")
                    NavigationLink {
                        LexiconView(lexicon: $model.lexicon, backup: model.lexiconBackup)
                    } label: {
                        LabeledContent("Lexicon", value: "\(model.lexicon.terms.count)")
                    }
                    .accessibilityIdentifier("settings.lexicon")
                }
                Section("Installed build") {
                    LabeledContent("Version", value: build.version)
                    LabeledContent("Commit", value: build.commit ?? "unknown")
                    LabeledContent("Built") {
                        if let builtAt = build.builtAt {
                            Text(builtAt, format: .dateTime.day().month().year().hour().minute())
                        } else {
                            Text("unknown")
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var languageLabel: String {
        switch model.dictationLanguage {
        case .iPhone:
            "Same as iPhone"
        case .specific(let identifier):
            DictationLanguage.name(of: Locale(identifier: identifier))
        }
    }
}
