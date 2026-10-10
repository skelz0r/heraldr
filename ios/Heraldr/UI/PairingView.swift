import SwiftUI
import VisionKit

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @State private var pairing = false
    @State private var error: String?
    @State private var scannedCode: String?

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    BrandMark(size: 34)
                    Text("Heraldr").font(.title2.weight(.heavy))
                }
                .padding(.top, 12)

                Text("Appairer le Mac")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sur le Mac, dans herdr :").font(.subheadline).foregroundStyle(.secondary)
                    Text("herdr plugin action invoke heeler.pair")
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Text("puis scanne le QR affiché, valable deux minutes.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))

                scanner
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    .overlay {
                        if pairing {
                            ZStack {
                                Rectangle().fill(.ultraThinMaterial)
                                VStack(spacing: 12) {
                                    ProgressView().controlSize(.large)
                                    Text("Enrôlement de l'iPhone…").font(.headline)
                                }
                            }
                            .clipShape(.rect(cornerRadius: 28, style: .continuous))
                        }
                    }

                if let error {
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AgentStatus.blocked.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                Button {
                    if let code = UIPasteboard.general.string { submit(code) }
                } label: {
                    Label("Coller le code d'appairage", systemImage: "doc.on.clipboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glass)
                .disabled(pairing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var scanner: some View {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            QRScanner { code in submit(code) }
        } else {
            ZStack {
                Rectangle().fill(.black.opacity(0.25))
                VStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 54))
                    Text("Caméra indisponible : colle le code à la place").font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func submit(_ code: String) {
        guard !pairing, code.hasPrefix(PairingCode.prefix), code != scannedCode else { return }
        scannedCode = code
        pairing = true
        error = nil
        Task {
            do {
                try await model.pair(code: code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.error = error.localizedDescription
                scannedCode = nil
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            pairing = false
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onCode(payload)
                }
            }
        }
    }
}
