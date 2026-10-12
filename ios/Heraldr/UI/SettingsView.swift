import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lexicon = DictationLexiconStore.load()
    private let build = BuildInfo.current

    var body: some View {
        NavigationStack {
            List {
                Section("Dictée") {
                    NavigationLink {
                        LexiconView(lexicon: $lexicon)
                    } label: {
                        LabeledContent("Corrections", value: "\(lexicon.corrections.count)")
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
            .onChange(of: lexicon) { DictationLexiconStore.save(lexicon) }
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
