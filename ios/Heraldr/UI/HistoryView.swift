import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copiedId: SentRequest.ID?
    @State private var copiedReset: Task<Void, Never>?

    enum Section: String, CaseIterable {
        case tasks = "Tâches"
        case questions = "Questions"
    }

    @State private var section: Section = .tasks

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .tasks: tasks
                case .questions: questions
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                Picker("Historique", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: SentRequest.ID.self) { id in
                if let entry = model.history.entries.first(where: { $0.id == id }), let answer = entry.answer {
                    AnswerContent(question: entry.text, answer: answer)
                        .navigationTitle(entry.targetLabel)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                CopyAnswerButton(answer: answer)
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var tasks: some View {
        if model.history.tasks.isEmpty {
            ContentUnavailableView(
                "Aucun envoi", systemImage: "clock.arrow.circlepath",
                description: Text("Les \(SendHistory.capacity) derniers envois s'afficheront ici."))
        } else {
            List(model.history.tasks) { entry in
                row(for: entry)
                    .swipeActions { deleteButton(for: entry) }
            }
        }
    }

    @ViewBuilder
    private var questions: some View {
        if model.history.questions.isEmpty {
            ContentUnavailableView(
                "Aucune question", systemImage: "text.bubble",
                description: Text("Les réponses aux \(SendHistory.capacity) dernières questions s'afficheront ici."))
        } else {
            List(model.history.questions) { entry in
                NavigationLink(value: entry.id) {
                    questionRow(for: entry)
                }
                .swipeActions { deleteButton(for: entry) }
            }
        }
    }

    private func deleteButton(for entry: SentRequest) -> some View {
        Button("Supprimer", systemImage: "trash", role: .destructive) {
            model.removeFromHistory(entry.id)
        }
    }

    private func questionRow(for entry: SentRequest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.targetLabel).font(.subheadline.weight(.bold))
                if let answer = entry.answer {
                    Text(answer.receivedAt, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(entry.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let answer = entry.answer {
                Text(answer.summary)
                    .font(.body)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(for entry: SentRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.targetLabel).font(.subheadline.weight(.bold))
                Text(entry.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                actions(for: entry)
                SentStatusBadge(status: entry.status)
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(4)
            if let attachments = entry.attachments {
                Text(attachments.count == 1 ? "1 capture jointe" : "\(attachments.count) captures jointes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if entry.status == .failed, let error = entry.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(SentRequest.Status.failed.color)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func actions(for entry: SentRequest) -> some View {
        let copied = copiedId == entry.id
        return HStack(spacing: 0) {
            actionButton("Renvoyer", systemImage: "arrow.clockwise") {
                resend(entry)
            }
            actionButton(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc", done: copied) {
                copy(entry)
            }
        }
        .padding(.vertical, -6)
    }

    private func actionButton(_ title: String, systemImage: String, done: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(done ? Color.heraldrAccent : Color(uiColor: .secondaryLabel))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }

    private func resend(_ entry: SentRequest) {
        dismiss()
        Task { await model.resend(entry) }
    }

    private func copy(_ entry: SentRequest) {
        UIPasteboard.general.string = entry.text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copiedId = entry.id }
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { copiedId = nil }
        }
    }
}

struct SentStatusBadge: View {
    let status: SentRequest.Status
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(status == .queued ? .clear : status.color)
            .strokeBorder(status == .queued ? status.color : .clear, lineWidth: 2)
            .frame(width: 10, height: 10)
            .background {
                if status == .sending {
                    Circle()
                        .fill(status.color.opacity(pulsing ? 0 : 0.7))
                        .scaleEffect(pulsing ? 2.5 : 1)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulsing)
                        .onAppear { pulsing = true }
                }
            }
            .padding(4)
            .accessibilityElement()
            .accessibilityLabel(status.label)
    }
}
