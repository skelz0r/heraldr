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
    @State private var stage: Stage = .preview
    @State private var text = ""
    @State private var origin: Origin = .written
    @State private var workspaceId: String = ""
    @State private var dictation = Dictation()
    @State private var lexicon = DictationLexiconStore.load()
    @State private var dictationError: String?
    @State private var dictatingFollowUp = false
    @State private var sending = false
    @State private var sendError: String?
    @State private var choosingTarget = false
    @State private var showingRaw = false
    @FocusState private var editorFocused: Bool

    private var target: Workspace? {
        model.workspaces.first { $0.id == workspaceId }
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
        .sheet(isPresented: $choosingTarget) {
            TargetPicker(selectedId: $workspaceId)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingRaw) {
            RawTranscriptSheet(origin: origin)
                .presentationDetents([.medium])
        }
    }

    private func configure() {
        workspaceId = request.workspaceId
        switch request.source {
        case .voice:
            stage = .recording
            Task { await startDictation() }
        case .write:
            origin = .written
            stage = .preview
            editorFocused = true
        case .paste(let pasted):
            origin = .pasted
            text = pasted
            stage = .preview
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
                .glassEffect(.regular.tint(.recording).interactive(), in: .circle)
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
                    Text(target?.label ?? "?").font(.title2.weight(.heavy)).lineLimit(1)
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
                Label("\(state.headline). \(state.nextSend)", systemImage: state.acceptsImmediately ? "checkmark.circle" : "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(state.acceptsImmediately ? Color.secondary : AgentStatus.working.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))

            HStack(spacing: 12) {
                originLine
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
            .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || target == nil)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
            try await model.send(text, to: target)
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
    @Binding var selectedId: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.workspaces) { workspace in
                Button {
                    selectedId = workspace.id
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        StatusDot(status: workspace.agentStatus)
                        Text(workspace.label).font(.body.weight(.semibold))
                        Spacer()
                        if !model.pendingJobs(for: workspace).isEmpty { WaitBadge(compact: true) }
                        if workspace.id == selectedId {
                            Image(systemName: "checkmark").foregroundStyle(Color.heraldrAccent)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .tint(.primary)
            }
            .navigationTitle("Changer de cible")
            .navigationBarTitleDisplayMode(.inline)
        }
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
