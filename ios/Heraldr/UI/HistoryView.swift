import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copiedId: SentRequest.ID?
    @State private var copiedReset: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if model.history.entries.isEmpty {
                    ContentUnavailableView(
                        "Aucun envoi", systemImage: "clock.arrow.circlepath",
                        description: Text("Les \(SendHistory.capacity) derniers envois s'afficheront ici."))
                } else {
                    List(model.history.entries) { entry in
                        row(for: entry)
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    model.removeFromHistory(entry.id)
                                }
                            }
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func row(for entry: SentRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(entry.workspaceLabel).font(.subheadline.weight(.bold))
                Text(entry.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                SentStatusBadge(status: entry.status)
            }
            Text(entry.text)
                .font(.body)
                .lineLimit(4)
            if entry.status == .failed, let error = entry.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AgentStatus.blocked.color)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button(copiedId == entry.id ? "Copié" : "Copier", systemImage: copiedId == entry.id ? "checkmark" : "doc.on.doc") {
                    copy(entry)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 4)
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

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
    }

    private var title: String {
        switch status {
        case .sending: "Envoi…"
        case .queued: "En file"
        case .sent: "Envoyé"
        case .failed: "Échec"
        }
    }

    private var icon: String {
        switch status {
        case .sending: "arrow.up.circle"
        case .queued: "clock"
        case .sent: "paperplane.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .sending, .queued: AgentStatus.working.color
        case .sent: AgentStatus.done.color
        case .failed: AgentStatus.blocked.color
        }
    }
}
