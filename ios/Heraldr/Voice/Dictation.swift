@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

enum DictationError: Error, LocalizedError {
    case microphoneDenied
    case localeUnsupported
    case noAudioFormat
    case audioEngine(String)
    case noMicrophone
    case step(String, any Error)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access denied: allow it in Settings"
        case .localeUnsupported:
            "Transcription in this language is not available on this iPhone"
        case .noAudioFormat:
            "No audio format compatible with transcription"
        case .audioEngine(let detail):
            "Microphone unavailable: \(detail)"
        case .noMicrophone:
            "No microphone available"
        case .step(let step, let error as DictationError):
            "\(step): \(error.localizedDescription)"
        case .step(let step, let error):
            "\(step): \(error.localizedDescription) (\((error as NSError).domain) \((error as NSError).code))"
        }
    }
}

@MainActor
@Observable
final class Dictation {
    enum Phase: Equatable {
        case idle
        case preparing
        case recording
        case finishing
    }

    private(set) var phase: Phase = .idle
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var startedAt: Date?
    private(set) var level: Float = 0

    private var analyzer: SpeechAnalyzer?
    private var feeder: AudioFeeder?
    private var engine: AVAudioEngine?
    private var resultsTask: Task<Void, Never>?

    var transcript: String {
        (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(locale requested: Locale, vocabulary: [String] = []) async throws {
        guard phase == .idle else { return }
        phase = .preparing
        finalizedText = ""
        volatileText = ""
        do {
            try await begin(locale: requested, vocabulary: vocabulary)
        } catch {
            teardown()
            throw error
        }
    }

    func stop() async -> String {
        guard phase == .recording else { return transcript }
        phase = .finishing
        releaseMicrophone()
        feeder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        let text = transcript
        teardown()
        return text
    }

    func cancel() async {
        releaseMicrophone()
        feeder?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        teardown()
    }

    private func begin(locale requested: Locale, vocabulary: [String]) async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw DictationError.microphoneDenied }

        let module: any SpeechModule
        let results: AsyncThrowingStream<(text: String, isFinal: Bool), any Error>
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            module = transcriber
            results = Self.stream(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: requested) {
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
            module = transcriber
            results = Self.stream(transcriber.results) { (String($0.text.characters), $0.isFinal) }
        } else {
            throw DictationError.localeUnsupported
        }

        try await Self.step("Downloading the transcription model") {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        }

        try Self.step("Setting up the audio session") {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }

        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw DictationError.noMicrophone }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: inputFormat) else {
            throw DictationError.noAudioFormat
        }
        let feeder = try Self.step("Converting audio") {
            try AudioFeeder(from: inputFormat, to: analyzerFormat) { [weak self] level in
                Task { @MainActor in self?.level = level }
            }
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await Self.step("Starting transcription") {
            if !vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocabulary
                try? await analyzer.setContext(context)
            }
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            try await analyzer.start(inputSequence: feeder.stream)
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in results {
                    self?.receive(result.text, isFinal: result.isFinal)
                }
            } catch {}
        }

        feeder.attach(to: engine.inputNode, format: inputFormat)
        engine.prepare()
        try Self.step("Starting the microphone") {
            try engine.start()
        }

        self.engine = engine
        self.feeder = feeder
        self.analyzer = analyzer
        startedAt = .now
        phase = .recording
    }

    private func receive(_ text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    private func releaseMicrophone() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardown() {
        releaseMicrophone()
        feeder = nil
        analyzer = nil
        resultsTask = nil
        startedAt = nil
        level = 0
        phase = .idle
    }

    private static func step<T>(_ name: String, _ operation: () throws -> T) throws -> T {
        do {
            return try operation()
        } catch {
            throw DictationError.step(name, error)
        }
    }

    private static func step<T>(_ name: String, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw DictationError.step(name, error)
        }
    }

    private static func stream<Results: AsyncSequence & Sendable>(
        _ results: Results,
        _ transform: @escaping @Sendable (Results.Element) -> (String, Bool)
    ) -> AsyncThrowingStream<(text: String, isFinal: Bool), any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await element in results {
                        let (text, isFinal) = transform(element)
                        continuation.yield((text, isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class AudioFeeder: @unchecked Sendable {
    let stream: AsyncStream<AnalyzerInput>
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private let reportLevel: @Sendable (Float) -> Void

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat, reportLevel: @escaping @Sendable (Float) -> Void) throws {
        (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.outputFormat = outputFormat
        self.reportLevel = reportLevel
        if inputFormat == outputFormat {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw DictationError.noAudioFormat
            }
            converter.primeMethod = .none
            self.converter = converter
        }
    }

    func attach(to input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, _ in
            feed(buffer)
        }
    }

    private func feed(_ buffer: AVAudioPCMBuffer) {
        reportLevel(Self.level(of: buffer))
        guard let converter else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let input = buffer
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if error == nil, converted.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() {
        continuation.finish()
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, rms * 12)
    }
}
