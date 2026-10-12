import SwiftUI

struct LexiconView: View {
    @Binding var lexicon: DictationLexicon
    let backup: LexiconKeeper.BackupState
    @State private var editing: TermDraft?

    var body: some View {
        Group {
            if lexicon.terms.isEmpty {
                ContentUnavailableView {
                    Label("No terms", systemImage: "text.badge.checkmark")
                } description: {
                    Text("Fix a misheard word in a dictation preview: the term is added here when you send, with what was heard.")
                } actions: {
                    Button("Add a term") { editing = TermDraft() }
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
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    lexicon.forget(term.id)
                                }
                            }
                        }
                    } footer: {
                        Text(
                            "Most recent first. A variant typed here, or one of several words, is replaced by its term in every dictation; a learned single-word variant is only hinted to the cleanup.\n\n\(backupStatus)"
                        )
                    }
                }
            }
        }
        .navigationTitle("Dictation lexicon")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add a term", systemImage: "plus") { editing = TermDraft() }
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
            "The lexicon backed up on the Mac will be restored at the next connection."
        case .changesPending:
            "Not backed up on the Mac yet: it will be at the next connection."
        case .savedOnMac(let date):
            "Backed up on the Mac \(date.formatted(.relative(presentation: .named)))."
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
                Section("Term") {
                    TextField("Term", text: $draft.text)
                }
                Section {
                    ForEach($draft.variants) { $variant in
                        TextField("Heard", text: $variant.heard)
                    }
                    .onDelete { draft.variants.remove(atOffsets: $0) }
                    Button("Add a variant") { draft.variants.append(.init(heard: "")) }
                } header: {
                    Text("Heard variants")
                } footer: {
                    Text("1 to \(DictationLexicon.maxWords) words for the term and each variant, each one different from the term and the others.")
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(draft.original == nil ? "New term" : "Edit term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        if save(draft.text, draft.heard) { dismiss() }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
