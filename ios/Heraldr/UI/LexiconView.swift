import SwiftUI

struct LexiconView: View {
    @Binding var lexicon: DictationLexicon
    let backup: LexiconKeeper.BackupState
    @State private var editing: TermDraft?

    var body: some View {
        Group {
            if lexicon.terms.isEmpty {
                ContentUnavailableView {
                    Label("Aucun terme", systemImage: "text.badge.checkmark")
                } description: {
                    Text("Corrige un mot mal entendu dans l'aperçu d'une dictée : le terme s'ajoutera ici à l'envoi, avec ce qui avait été entendu.")
                } actions: {
                    Button("Ajouter un terme") { editing = TermDraft() }
                }
            } else {
                List {
                    Section {
                        ForEach(lexicon.terms) { term in
                            Button {
                                editing = TermDraft(term)
                            } label: {
                                row(for: term)
                            }
                            .tint(.primary)
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    lexicon.forget(term.id)
                                }
                            }
                        }
                    } footer: {
                        Text(
                            "Les plus récents d'abord. Une variante saisie ici, ou de plusieurs mots, est remplacée par son terme dans chaque dictée ; une variante apprise d'un seul mot est seulement signalée au nettoyage.\n\n\(backupStatus)"
                        )
                    }
                }
            }
        }
        .navigationTitle("Lexique de dictée")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ajouter un terme", systemImage: "plus") { editing = TermDraft() }
                    .accessibilityIdentifier("lexicon.add")
            }
        }
        .sheet(item: $editing) { draft in
            TermForm(draft: draft) { text, heard in
                lexicon.define(text, heard: heard, replacing: draft.original)
            }
        }
    }

    private var backupStatus: String {
        switch backup {
        case .restorePending:
            "Le lexique sauvegardé sur le Mac sera repris à la prochaine connexion."
        case .changesPending:
            "Pas encore sauvegardé sur le Mac : ce sera fait à la prochaine connexion."
        case .savedOnMac(let date):
            "Sauvegardé sur le Mac \(date.formatted(.relative(presentation: .named)))."
        }
    }

    private func row(for term: DictationTerm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term.text).foregroundStyle(.primary)
            if !term.variants.isEmpty {
                Text(term.variants.map(\.heard).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TermDraft: Identifiable {
    struct Variant: Identifiable {
        let id = UUID()
        var heard: String
    }

    let id = UUID()
    var original: DictationTerm.ID?
    var text = ""
    var variants = [Variant(heard: "")]

    init() {}

    init(_ term: DictationTerm) {
        original = term.id
        text = term.text
        variants = term.variants.map { Variant(heard: $0.heard) } + [Variant(heard: "")]
    }

    var heard: [String] { variants.map(\.heard) }
}

private struct TermForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TermDraft
    let save: (String, [String]) -> Bool

    init(draft: TermDraft, save: @escaping (String, [String]) -> Bool) {
        _draft = State(initialValue: draft)
        self.save = save
    }

    private var isValid: Bool {
        DictationLexicon.validated(draft.text, heard: draft.heard) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Terme") {
                    TextField("Terme", text: $draft.text)
                }
                Section {
                    ForEach($draft.variants) { $variant in
                        TextField("Entendu", text: $variant.heard)
                    }
                    .onDelete { draft.variants.remove(atOffsets: $0) }
                    Button("Ajouter une variante") { draft.variants.append(.init(heard: "")) }
                } header: {
                    Text("Variantes entendues")
                } footer: {
                    Text("De 1 à \(DictationLexicon.maxWords) mots pour le terme et pour chaque variante, chacune différente du terme et des autres.")
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(draft.original == nil ? "Nouveau terme" : "Modifier le terme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if save(draft.text, draft.heard) { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
