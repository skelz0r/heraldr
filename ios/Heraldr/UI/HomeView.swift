import SwiftUI
import UIKit

struct ComposeRequest: Identifiable {
    enum Source {
        case voice
        case write
        case paste(String)
    }

    let id = UUID()
    let source: Source
    let workspaceId: String
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var compose: ComposeRequest?
    @State private var confirmingForget = false
    @State private var showingHistory = false
    @State private var showingSettings = false

    private let orbSize: CGFloat = 104
    private let barHeight: CGFloat = 92

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            workspaceGrid
        }
        .overlay(alignment: .top) {
            if let question = model.unopenedQuestion {
                UnopenedQuestionCard(question: question) { model.unopenedQuestion = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let notice = model.notice {
                NoticeToast(notice: notice)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.notice = nil }
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation { model.notice = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: model.notice)
        .animation(.spring(duration: 0.35), value: model.unopenedQuestion)
        .fullScreenCover(item: $compose) { request in
            ComposeView(request: request)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.medium])
        }
        .confirmationDialog("Oublier ce Mac ?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Oublier et réappairer", role: .destructive) {
                Task { await model.forgetMac() }
            }
        } message: {
            Text("La clé de cet iPhone restera autorisée sur le Mac tant que tu ne la retires pas de ~/.ssh/authorized_keys.")
        }
    }

    private var targetHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                macPill
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    historyButton
                    settingsButton
                }
            }
            .padding(.bottom, 10)
            if let target = model.selectedWorkspace {
                Text("CIBLE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(target.label)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                    .contentTransition(.opacity)
                let state = model.targetState(for: target)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StatusDot(status: state.dotStatus)
                        Text(state.headline)
                            .font(.callout.weight(.semibold))
                    }
                    Text("\(AgentName.forWorkspace(label: target.label)) · \(state.nextSend)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.leading, 18)
                }
                .padding(.top, 6)
            } else {
                connectionState
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var connectionState: some View {
        switch model.connection {
        case .unreachable(let detail):
            VStack(alignment: .leading, spacing: 12) {
                Label("Mac injoignable", systemImage: "wifi.exclamationmark")
                    .font(.title2.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                Button("Réessayer") { Task { await model.refresh() } }
                    .buttonStyle(.glassProminent)
            }
        default:
            HStack(spacing: 10) {
                ProgressView()
                Text("Connexion au Mac…").foregroundStyle(.secondary)
            }
        }
    }

    private var macPill: some View {
        Menu {
            Button("Rafraîchir", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
            Button("Oublier ce Mac", systemImage: "xmark.circle", role: .destructive) { confirmingForget = true }
        } label: {
            HStack(spacing: 8) {
                BrandMark(size: 20)
                Text("Heraldr").font(.subheadline.weight(.heavy))
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 1, height: 14)
                StatusDot(status: macStatus, size: 8)
                Text(macName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .tint(.primary)
    }

    private var historyButton: some View {
        roundButton("Historique des envois", systemImage: "clock.arrow.circlepath") { showingHistory = true }
    }

    private var settingsButton: some View {
        roundButton("Réglages", systemImage: "gearshape") { showingSettings = true }
    }

    private func roundButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private var macName: String {
        guard let mac = model.mac else { return "Mac" }
        return "\(mac.username)@\(mac.addresses.first ?? "?")"
    }

    private var macStatus: AgentStatus {
        switch model.connection {
        case .online: .done
        case .connecting: .working
        case .unreachable: .blocked
        case .unpaired: .idle
        }
    }

    private var workspaceGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.workspaces) { workspace in
                    tile(for: workspace)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .safeAreaBar(edge: .top) { targetHeader }
        .safeAreaBar(edge: .bottom) { actionBar }
        .refreshable { await model.refresh() }
    }

    private func tile(for workspace: Workspace) -> some View {
        WorkspaceTile(
            workspace: workspace,
            isSelected: workspace.id == model.selectedWorkspace?.id,
            isQueued: !model.pendingJobs(for: workspace).isEmpty
        ) {
            withAnimation(.snappy) { model.selectedWorkspaceId = workspace.id }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private var actionBar: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                sideButton("Écrire", systemImage: "pencil") { open(.write) }
                Spacer().frame(width: orbSize + 12)
                sideButton("Coller", systemImage: "doc.on.clipboard") { paste() }
            }
            .frame(height: barHeight)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12)

            VoiceOrb(size: orbSize) { open(.voice) }
                .padding(.bottom, 10)
        }
        .padding(.bottom, 4)
        .disabled(model.selectedWorkspace == nil)
    }

    private func sideButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(height: 32)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func open(_ source: ComposeRequest.Source) {
        guard let target = model.selectedWorkspace else { return }
        compose = ComposeRequest(source: source, workspaceId: target.id)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            model.notice = AppModel.Notice(kind: .failed, title: "Presse-papier vide", detail: "Copie d'abord le texte à envoyer.")
            return
        }
        open(.paste(text))
    }
}

struct WorkspaceTile: View {
    let workspace: Workspace
    let isSelected: Bool
    let isQueued: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusDot(status: workspace.agentStatus)
                    .overlay {
                        if isSelected { Circle().stroke(Color.onAccent, lineWidth: 2).padding(-2) }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.label)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(workspace.agentStatus.label)
                        .font(.footnote)
                        .foregroundStyle(isSelected ? Color.onAccent.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                    if isQueued { WaitBadge(compact: true).padding(.top, 2) }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .foregroundStyle(isSelected ? Color.onAccent : Color.primary)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.heraldrAccent).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 20, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary, lineWidth: 2.5)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct VoiceOrb: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(Color.onAccent)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.heraldrAccent).interactive(), in: .circle)
        .background {
            Circle()
                .stroke(Color.wallBase, lineWidth: 10)
                .shadow(color: Color.heraldrAccent.opacity(0.35), radius: 16, y: 8)
        }
        .accessibilityLabel("Dicter")
    }
}
