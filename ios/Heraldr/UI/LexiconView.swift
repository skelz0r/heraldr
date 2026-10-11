import SwiftUI

struct LexiconView: View {
    @Binding var lexicon: DictationLexicon
    @State private var editing: CorrectionDraft?

    var body: some View {
        Group {
            if lexicon.corrections.isEmpty {
                ContentUnavailableView {
                    Label("Aucune correction", systemImage: "text.badge.checkmark")
                } description: {
                    Text("Corrige un mot mal entendu dans l'aperçu d'une dictée : la correction s'ajoutera ici à l'envoi.")
                } actions: {
                    Button("Ajouter une correction") { editing = CorrectionDraft() }
                }
            } else {
                List {
                    Section {
                        ForEach(lexicon.corrections) { correction in
                            Button { editing = CorrectionDraft(correction) } label: {
                                row(for: correction)
                            }
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    lexicon.forget(heard: correction.heard)
                                }
                            }
                        }
                    } footer: {
                        Text("\(lexicon.corrections.count) sur \(DictationLexicon.capacity), les plus récentes d'abord. Les \(DictationLexicon.promptedCorrections) premières guident le nettoyage.")
                    }
                }
            }
        }
        .navigationTitle("Corrections de dictée")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ajouter une correction", systemImage: "plus") { editing = CorrectionDraft() }
            }
        }
        .sheet(item: $editing) { draft in
            CorrectionForm(draft: draft) { heard, meant in
                lexicon.correct(heard: heard, meant: meant, replacing: draft.original)
            }
        }
    }

    private func row(for correction: DictationCorrection) -> some View {
        HStack(spacing: 8) {
            Text(correction.heard).foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("devient")
            Text(correction.meant).foregroundStyle(.primary)
        }
    }
}

struct CorrectionDraft: Identifiable {
    let id = UUID()
    var original: String?
    var heard = ""
    var meant = ""

    init() {}

    init(_ correction: DictationCorrection) {
        original = correction.heard
        heard = correction.heard
        meant = correction.meant
    }
}

private struct CorrectionForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CorrectionDraft
    let save: (String, String) -> Bool

    init(draft: CorrectionDraft, save: @escaping (String, String) -> Bool) {
        _draft = State(initialValue: draft)
        self.save = save
    }

    private var isValid: Bool {
        DictationLexicon.normalized(heard: draft.heard, meant: draft.meant) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Entendu", text: $draft.heard)
                    TextField("Voulu", text: $draft.meant)
                } footer: {
                    Text("De 1 à \(DictationLexicon.maxWordsPerSide) mots de chaque côté, et un voulu différent de l'entendu.")
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(draft.original == nil ? "Nouvelle correction" : "Modifier la correction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if save(draft.heard, draft.meant) { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
