import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private let build = BuildInfo.current

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Dictée") {
                    NavigationLink {
                        LexiconView(lexicon: $model.lexicon, backup: model.lexiconBackup)
                    } label: {
                        LabeledContent("Lexique", value: "\(model.lexicon.terms.count)")
                    }
                }
                Section("Build installé") {
                    LabeledContent("Version", value: build.version)
                    LabeledContent("Commit", value: build.commit ?? "inconnu")
                    LabeledContent("Buildé") {
                        if let builtAt = build.builtAt {
                            Text(builtAt, format: .dateTime.day().month().year().hour().minute())
                        } else {
                            Text("inconnu")
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
