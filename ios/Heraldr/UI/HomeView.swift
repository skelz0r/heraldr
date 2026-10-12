import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposeRequest: Identifiable {
    enum Source {
        case voice
        case write
        case paste(String, images: [NSItemProvider])
    }

    let id = UUID()
    let source: Source
    let workspaceId: String
    let tabId: String?
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var compose: ComposeRequest?
    @State private var confirmingForget = false
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var targetBottom: CGFloat = 0

    private let targetShare: CGFloat = 0.38
    private let gridFadeHeight: CGFloat = 56

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
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Oublier ce Mac ?", isPresented: $confirmingForget, titleVisibility: .visible) {
            Button("Oublier et réappairer", role: .destructive) {
                Task { await model.forgetMac() }
            }
        } message: {
            Text("La clé de cet iPhone restera autorisée sur le Mac tant que tu ne la retires pas de ~/.ssh/authorized_keys.")
        }
    }

    private var readArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                macPill
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    historyButton
                    settingsButton
                }
            }
            Spacer(minLength: 12)
            if let target = model.selectedTarget {
                Text("CIBLE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(target.workspace.label)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .tracking(-1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)
                    .contentTransition(.opacity)
                Text(target.tabName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                let state = model.targetState(for: target)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StatusDot(status: state.dotStatus)
                        Text(state.headline)
                            .font(.callout.weight(.semibold))
                    }
                    Text(state.nextSend(to: target))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }
                .padding(.top, 10)
            } else {
                connectionState
            }
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerRelativeFrame(.vertical, alignment: .top) { height, _ in height * targetShare }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { targetBottom = $0 }
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
                macDot
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

    @ViewBuilder
    private var macDot: some View {
        switch model.connection {
        case .online: Circle().fill(Color.macOnline).frame(width: 8, height: 8).accessibilityLabel("En ligne")
        case .connecting: StatusDot(status: .working, size: 8)
        case .unreachable: StatusDot(status: .blocked, size: 8)
        case .unpaired: StatusDot(status: .unknown, size: 8)
        }
    }

    private var workspaceGrid: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let first = model.workspaces.first {
                    tile(for: first)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(model.workspaces.dropFirst()) { workspace in
                        tile(for: workspace)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .mask {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: max(targetBottom - gridFadeHeight, 0))
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: gridFadeHeight)
                Color.black
            }
            .ignoresSafeArea()
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .safeAreaBar(edge: .top) { readArea }
        .safeAreaBar(edge: .bottom) { actionBar }
        .refreshable { await model.refresh() }
    }

    private func tile(for workspace: Workspace) -> some View {
        WorkspaceTile(
            workspace: workspace,
            status: model.targetState(for: workspace).dotStatus,
            isSelected: workspace.id == model.selectedWorkspace?.id,
            targetedTab: workspace.id == model.selectedWorkspace?.id ? model.selectedTarget?.tab : nil,
            isQueued: !model.pendingJobs(for: workspace).isEmpty
        ) {
            select(workspace)
        }
        .contextMenu {
            Section("Cibler un tab de \(workspace.label)") {
                Button(Tab.mainName) { select(workspace) }
                let tabs = model.claudeTabs(of: workspace)
                ForEach(tabs) { tab in
                    Button(tab.displayName) { select(workspace, tab: tab) }
                }
                if tabs.isEmpty {
                    Text("Aucun Claude dans les autres tabs")
                }
            }
        }
    }

    private func select(_ workspace: Workspace, tab: Tab? = nil) {
        withAnimation(.snappy) { model.select(workspace, tab: tab) }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            sideButton("Écrire", systemImage: "pencil") { open(.write) }
            VoiceDrop { open(.voice) }
            sideButton("Coller", systemImage: "doc.on.clipboard") { paste() }
        }
        .padding(.bottom, 8)
        .disabled(model.selectedWorkspace == nil)
    }

    private func sideButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 54, height: 54)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(title)
    }

    private func open(_ source: ComposeRequest.Source) {
        guard let target = model.selectedTarget else { return }
        compose = ComposeRequest(source: source, workspaceId: target.workspace.id, tabId: target.tab?.id)
    }

    private func paste() {
        let pasteboard = UIPasteboard.general
        let text = pasteboard.hasStrings ? pasteboard.string ?? "" : ""
        let images = pasteboard.hasImages ? pasteboard.itemProviders.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) } : []
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            model.notice = AppModel.Notice(
                kind: .failed, title: "Presse-papier vide", detail: "Copie d'abord le texte ou la capture à envoyer.")
            return
        }
        open(.paste(text, images: images))
    }
}

struct WorkspaceTile: View {
    let workspace: Workspace
    let status: AgentStatus
    let isSelected: Bool
    let targetedTab: Tab?
    let isQueued: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                StatusDot(status: status)
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.label)
                        .font(.system(size: 15, weight: isSelected ? .bold : .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let targetedTab {
                        Text(targetedTab.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if isQueued { WaitBadge(compact: true) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.selectedGlass).interactive() : .regular.tint(.restingGlass).interactive(),
            in: .rect(cornerRadius: 20, style: .continuous))
        .shadow(color: isSelected ? .selectedGlow : .clear, radius: 13, y: 6)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct VoiceDrop: View {
    let action: () -> Void
    private let size: CGFloat = 92

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.voiceInk)
                .shadow(color: Color.voiceGlow.opacity(0.7), radius: 4)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(RadialGradient(
                        colors: [Color.voiceGlow.opacity(0.55), Color.voiceGlow.opacity(0)],
                        center: UnitPoint(x: 0.5, y: 1.15),
                        startRadius: 0,
                        endRadius: size * 0.78))
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .accessibilityLabel("Dicter")
    }
}
