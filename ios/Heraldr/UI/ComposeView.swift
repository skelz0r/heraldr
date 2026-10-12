import PhotosUI
import SwiftUI

struct ComposeView: View {
    enum Stage: Equatable {
        case recording
        case cleaning(raw: String)
        case preview
    }

    enum Origin: Equatable {
        case written
        case pasted
        case dictated(DictatedText)
    }

    let request: ComposeRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var stage: Stage = .preview
    @State private var text = ""
    @State private var origin: Origin = .written
    @State private var workspaceId: String = ""
    @State private var tabId: String?
    @State private var clearsContext = false
    @State private var slots: [AttachmentSlot] = []
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var importFailed = false
    @State private var dictation = Dictation()
    @State private var lexicon = DictationLexiconStore.load()
    @State private var dictationError: String?
    @State private var dictatingFollowUp = false
    @State private var sending = false
    @State private var sendError: String?
    @State private var choosingTarget = false
    @State private var showingRaw = false
    @FocusState private var editorFocused: Bool

    private var target: Target? {
        guard let workspace = model.workspaces.first(where: { $0.id == workspaceId }) else { return nil }
        let target = model.target(in: workspace, tabId: tabId)
        return tabVanished(from: target) ? nil : target
    }

    private var targetVanished: Bool {
        guard let workspace = model.workspaces.first(where: { $0.id == workspaceId }) else { return false }
        return tabVanished(from: model.target(in: workspace, tabId: tabId))
    }

    private func tabVanished(from target: Target) -> Bool {
        tabId != nil && target.tab == nil
    }

    private var keepsScreenAwake: Bool {
        dictation.phase != .idle && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Wallpaper()
            switch stage {
            case .recording: recordingStage
            case .cleaning(let raw): cleaningStage(raw)
            case .preview: previewStage
            }
        }
        .animation(.smooth, value: stage)
        .onAppear(perform: configure)
        .onChange(of: keepsScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $choosingTarget) {
            TargetPicker(workspaceId: $workspaceId, tabId: $tabId)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: tabId) { clearsContext = false }
        .sheet(isPresented: $showingRaw) {
            RawTranscriptSheet(origin: origin)
                .presentationDetents([.medium])
        }
    }

    private func configure() {
        workspaceId = request.workspaceId
        tabId = request.tabId
        switch request.source {
        case .voice:
            stage = .recording
            Task { await startDictation() }
        case .write:
            origin = .written
            stage = .preview
            editorFocused = true
        case .paste(let pasted, let images):
            origin = .pasted
            text = pasted
            stage = .preview
            enqueueImports(images.map { provider in { await provider.loadImageData() } })
        }
    }

    private var targetPill: some View {
        Label(target?.label ?? "?", systemImage: "arrow.right")
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
    }

    private var recordingStage: some View {
        VStack(spacing: 0) {
            targetPill.padding(.top, 12)
            ScrollView {
                Group {
                    if let dictationError {
                        Text(dictationError).foregroundStyle(AgentStatus.blocked.color)
                    } else if dictation.phase == .preparing {
                        Text("Préparation du micro…").foregroundStyle(.secondary)
                    } else if dictation.finalizedText.isEmpty && dictation.volatileText.isEmpty {
                        Text("Parle, je t'écoute.").foregroundStyle(.secondary)
                    } else {
                        Text("\(dictation.finalizedText)\(Text(dictation.volatileText).foregroundStyle(.secondary))")
                    }
                }
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .defaultScrollAnchor(.bottom)

            LevelWave(level: dictation.level)
                .frame(height: 64)
                .padding(.horizontal, 32)
            if let startedAt = dictation.startedAt {
                Text(startedAt, style: .timer)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            HStack(spacing: 40) {
                Button {
                    Task { await cancelDictation() }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 24, weight: .bold)).frame(width: 64, height: 64)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Annuler")

                Button {
                    Task { await finishDictation() }
                } label: {
                    RoundedRectangle(cornerRadius: 10).fill(.white).frame(width: 36, height: 36)
                        .frame(width: 112, height: 112)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.heraldrAccent).interactive(), in: .circle)
                .disabled(dictation.phase != .recording)
                .accessibilityLabel("Arrêter la dictée")

                Color.clear.frame(width: 64, height: 64)
            }
            .padding(.vertical, 28)
        }
    }

    private func cleaningStage(_ raw: String) -> some View {
        VStack(spacing: 24) {
            targetPill.padding(.top, 12)
            Text(raw)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                Text("Nettoyage…")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .capsule)
            .phaseAnimator([0.5, 1]) { content, phase in content.opacity(phase) }
            Text("Foundation Models, sur l'appareil").font(.footnote).foregroundStyle(.secondary)
                .padding(.bottom, 40)
        }
    }

    private var previewStage: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Fermer")
                Spacer()
                Text("Aperçu").font(.headline)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }

            Button { choosingTarget = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right").font(.title3.weight(.heavy)).foregroundStyle(Color.heraldrAccent)
                    Text(target?.label ?? "?").font(.title2.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    if let target {
                        StatusDot(status: model.targetState(for: target).dotStatus)
                    }
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))

            if let target {
                let state = model.targetState(for: target)
                Label("\(state.headline). \(state.nextSend(to: target, clearingContext: clearsContext))", systemImage: state.acceptsImmediately ? "checkmark.circle" : "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(state.acceptsImmediately ? Color.secondary : AgentStatus.working.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $text)
                    .font(.system(size: 19, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .focused($editorFocused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Que doit faire l'agent ?")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                if !slots.isEmpty {
                    attachmentStrip
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))

            HStack(spacing: 8) {
                originLine
                PhotosPicker(
                    selection: $pickedPhotos, maxSelectionCount: max(remainingSlots, 1),
                    selectionBehavior: .ordered, matching: .images
                ) {
                    Image(systemName: "photo.badge.plus")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(sending || remainingSlots == 0)
                .accessibilityLabel("Joindre des captures")
                .onChange(of: pickedPhotos) { _, picked in
                    guard !picked.isEmpty else { return }
                    pickedPhotos = []
                    enqueueImports(picked.map { item in { try? await item.loadTransferable(type: Data.self) } })
                }
                Button { dictateFollowUp() } label: {
                    Label(text.isEmpty ? "Dicter" : "Dicter la suite", systemImage: "mic.fill")
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(sending)
            }

            if target?.tab != nil {
                Button { clearsContext.toggle() } label: {
                    Label("Envoyer /clear avant", systemImage: clearsContext ? "checkmark.square.fill" : "square")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(clearsContext ? .isSelected : [])
            }

            if targetVanished {
                Text("Ce tab n'existe plus : choisis une autre cible.").font(.footnote).foregroundStyle(AgentStatus.blocked.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if importFailed {
                Text("Une image n'a pas pu être lue.").font(.footnote).foregroundStyle(AgentStatus.blocked.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let sendError {
                Text(sendError).font(.footnote).foregroundStyle(AgentStatus.blocked.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 10) {
                    if sending { ProgressView().tint(Color.onAccent) } else { Image(systemName: "arrow.up") }
                    Text("Envoyer")
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.heraldrAccent).interactive(), in: .capsule)
            .disabled(
                sending || importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target == nil)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private static let thumbnailHeight: CGFloat = 84

    private func thumbnailWidth(_ image: UIImage) -> CGFloat {
        let ratio = image.size.width / max(image.size.height, 1)
        return Self.thumbnailHeight * min(max(ratio, 0.6), 1.4)
    }

    private var attachmentStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                Group {
                    if let attachment = slot.attachment {
                        Image(uiImage: attachment.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: thumbnailWidth(attachment.thumbnail), height: Self.thumbnailHeight)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.2), lineWidth: 0.5)
                            }
                            .accessibilityLabel("Capture \(index + 1)")
                    } else {
                        ProgressView()
                            .frame(width: Self.thumbnailHeight * 0.6, height: Self.thumbnailHeight)
                            .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
                            .accessibilityLabel("Capture \(index + 1) en préparation")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { remove(slot) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .heavy))
                            .frame(width: 20, height: 20)
                            .glassEffect(.regular, in: .circle)
                            .padding(4)
                            .frame(width: 40, height: 40, alignment: .topTrailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(sending)
                    .accessibilityLabel("Retirer la capture \(index + 1)")
                }
                .accessibilityElement(children: .contain)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: slots.map(\.id))
    }

    @ViewBuilder
    private var originLine: some View {
        HStack(spacing: 8) {
            switch origin {
            case .written:
                Label("Écrit", systemImage: "pencil")
            case .pasted:
                Label("Collé", systemImage: "doc.on.clipboard")
            case .dictated(let dictated):
                if let reason = dictated.salves.lastRawReason {
                    Label("Transcription brute : \(reason)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AgentStatus.blocked.color)
                } else {
                    Label("Dictée nettoyée", systemImage: "sparkles")
                }
                if dictated.salves.contains(where: \.isCleaned) {
                    Button("Voir l'original") { showingRaw = true }.foregroundStyle(Color.heraldrAccent)
                }
            }
            Spacer()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var remainingSlots: Int {
        max(ImageAttachment.limit - slots.count, 0)
    }

    private var importing: Bool {
        slots.contains { $0.attachment == nil }
    }

    private func enqueueImports(_ loaders: [() async -> Data?]) {
        let loaders = loaders.prefix(remainingSlots)
        guard !loaders.isEmpty else { return }
        importFailed = false
        for load in loaders {
            let slot = AttachmentSlot()
            slots.append(slot)
            Task {
                let data = await load()
                let attachment = await Task.detached { data.flatMap(ImageAttachment.init(imageData:)) }.value
                guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
                if let attachment {
                    slots[index].attachment = attachment
                } else {
                    slots.remove(at: index)
                    importFailed = true
                }
            }
        }
    }

    private func remove(_ slot: AttachmentSlot) {
        slots.removeAll { $0.id == slot.id }
    }

    private func startDictation() async {
        dictationError = nil
        do {
            try await dictation.start(vocabulary: lexicon.vocabulary)
        } catch {
            dictationError = error.localizedDescription
        }
    }

    private func finishDictation() async {
        let raw = await dictation.stop()
        guard !raw.isEmpty else {
            dictationError = "Rien n'a été entendu."
            return
        }
        stage = .cleaning(raw: raw)
        let cleaned = await TranscriptCleaner.clean(raw, lexicon: lexicon)
        append(cleaned)
        stage = .preview
    }

    private func append(_ salve: CleanedTranscript) {
        let dictated = if case .dictated(let dictated) = origin {
            dictated.appending(salve, after: text)
        } else {
            DictatedText(salve, after: text)
        }
        text = dictated.text
        origin = .dictated(dictated)
    }

    private func dictateFollowUp() {
        editorFocused = false
        sendError = nil
        dictatingFollowUp = true
        stage = .recording
        Task { await startDictation() }
    }

    private func cancelDictation() async {
        await dictation.cancel()
        guard dictatingFollowUp else {
            dismiss()
            return
        }
        dictationError = nil
        stage = .preview
    }

    private func send() async {
        guard let target else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        lexicon.learn(sent: text, origin: origin)
        DictationLexiconStore.save(lexicon)
        do {
            try await model.send(
                text, images: slots.compactMap(\.attachment?.jpeg), to: target, clearingContext: target.tab != nil && clearsContext)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            sendError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct LevelWave: View {
    let level: Float
    private let bars = 21

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<bars, id: \.self) { index in
                    let phase = sin(time * 6 + Double(index) * 0.7) * 0.5 + 0.5
                    let height = 8 + CGFloat(level) * 56 * CGFloat(0.35 + 0.65 * phase)
                    Capsule()
                        .fill(Color.heraldrAccent)
                        .frame(width: 5, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct TargetPicker: View {
    @Binding var workspaceId: String
    @Binding var tabId: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.workspaces) { workspace in
                Section {
                    row(Target(workspace), title: workspace.label, isQueued: !model.pendingJobs(for: workspace).isEmpty)
                    ForEach(model.claudeTabs(of: workspace)) { tab in
                        row(Target(workspace, tab: tab), title: tab.displayName, isQueued: !model.pendingJobs(for: tab).isEmpty)
                            .padding(.leading, 22)
                    }
                }
            }
            .navigationTitle("Changer de cible")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ target: Target, title: String, isQueued: Bool) -> some View {
        Button {
            workspaceId = target.workspace.id
            tabId = target.tab?.id
            dismiss()
        } label: {
            HStack(spacing: 12) {
                StatusDot(status: model.targetState(for: target).dotStatus)
                Text(title).font(.body.weight(target.tab == nil ? .semibold : .regular))
                Spacer()
                if isQueued { WaitBadge(compact: true) }
                if target.workspace.id == workspaceId && target.tab?.id == tabId {
                    Image(systemName: "checkmark").foregroundStyle(Color.heraldrAccent)
                }
            }
            .frame(minHeight: 44)
        }
        .tint(.primary)
        .accessibilityLabel(target.label)
    }
}

struct RawTranscriptSheet: View {
    let origin: ComposeView.Origin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcription originale").font(.headline)
                if case .dictated(let dictated) = origin {
                    ForEach(Array(dictated.salves.enumerated()), id: \.offset) { index, salve in
                        if index > 0 { Divider() }
                        Text(salve.raw).textSelection(.enabled)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension CleanedTranscript {
    var isCleaned: Bool {
        if case .cleaned = self { true } else { false }
    }
}

private extension [CleanedTranscript] {
    var lastRawReason: String? {
        reversed().lazy.compactMap { salve -> String? in
            if case .raw(_, let reason) = salve { reason } else { nil }
        }.first
    }
}

struct AttachmentSlot: Identifiable {
    let id = UUID()
    var attachment: ImageAttachment?
}
