import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let build = BuildInfo.current

    var body: some View {
        NavigationStack {
            List {
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
