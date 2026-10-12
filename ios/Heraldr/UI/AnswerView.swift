import SwiftUI
import UIKit

struct AnswerSheet: View {
    let presented: AppModel.PresentedAnswer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AnswerContent(
                question: presented.question, answer: presented.answer, loading: presented.loading,
                failure: presented.failure)
            .navigationTitle(presented.targetLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CopyAnswerButton(answer: presented.answer)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}

struct AnswerContent: View {
    let question: String?
    let answer: Answer
    var loading = false
    var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let question {
                    Text(question)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(answer.summary)
                    .font(.title3.weight(.semibold))
                if !answer.body.isEmpty && answer.body != answer.summary {
                    MarkdownText(source: answer.body)
                }
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Chargement de la réponse complète")
                }
                if let failure {
                    Text(failure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

struct CopyAnswerButton: View {
    let answer: Answer
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.string = answer.body.isEmpty ? answer.summary : answer.body
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { copied = true }
        }
        .contentTransition(.symbolEffect(.replace))
        .tint(copied ? Color.heraldrAccent : Color(uiColor: .secondaryLabel))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }
}

struct MarkdownText: View {
    enum Block: Hashable {
        case heading(String)
        case paragraph(String)
        case item(marker: String, text: String)
        case code(String)
    }

    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.blocks(of: source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let text):
            Text(Self.inline(text)).font(.headline)
        case .paragraph(let text):
            Text(Self.inline(text)).font(.body)
        case .item(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(Self.inline(text))
            }
            .font(.body)
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.footnote.monospaced())
                    .padding(12)
            }
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        }
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    static func blocks(of source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = trimmed.wholeMatch(of: #/#{1,6}\s+(.+)/#) {
                flushParagraph()
                blocks.append(.heading(String(heading.1)))
            } else if let bullet = trimmed.wholeMatch(of: #/[-*+]\s+(.+)/#) {
                flushParagraph()
                blocks.append(.item(marker: "•", text: String(bullet.1)))
            } else if let numbered = trimmed.wholeMatch(of: #/(\d+[.)])\s+(.+)/#) {
                flushParagraph()
                blocks.append(.item(marker: String(numbered.1), text: String(numbered.2)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }
}
