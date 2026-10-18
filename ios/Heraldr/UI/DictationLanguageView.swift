import SwiftUI

struct DictationLanguageView: View {
    @Binding var language: DictationLanguage
    let supportedLocales: () async -> [Locale]
    @State private var locales: [Locale]?

    var body: some View {
        List {
            Section {
                row(
                    title: "Same as iPhone",
                    subtitle: DictationLanguage.name(of: DictationLanguage.iPhone.locale()),
                    selected: language == .iPhone,
                    identifier: "dictationLanguage.iPhone"
                ) { language = .iPhone }
            } footer: {
                Text("Only the microphone listens in this language: the app stays in English. Applies from the next dictation.")
            }
            Section("Languages") {
                if let locales {
                    ForEach(locales, id: \.self) { locale in
                        let identifier = locale.identifier(.bcp47)
                        row(
                            title: DictationLanguage.name(of: locale),
                            selected: language == .specific(identifier),
                            identifier: "dictationLanguage.\(identifier)"
                        ) { language = .specific(identifier) }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Dictation language")
        .task { locales = await supportedLocales() }
    }

    private func row(title: String, subtitle: String? = nil, selected: Bool, identifier: String, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.heraldrAccent)
                }
            }
        }
        .tint(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
