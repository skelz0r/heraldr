import UIKit
import UniformTypeIdentifiers

struct ImageAttachment: Identifiable, Sendable {
    static let limit = 3
    static let longestSide: CGFloat = 1568
    static let jpegQuality: CGFloat = 0.85

    let id = UUID()
    let thumbnail: UIImage
    let jpeg: Data

    init?(imageData: Data) {
        guard let image = UIImage(data: imageData) else { return nil }
        let scale = min(1, Self.longestSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = resized.jpegData(compressionQuality: Self.jpegQuality) else { return nil }
        self.jpeg = jpeg
        thumbnail =
            resized.preparingThumbnail(
                of: CGSize(width: size.width * 240 / max(size.width, size.height), height: size.height * 240 / max(size.width, size.height))) ?? resized
    }
}

extension NSItemProvider {
    @MainActor func loadImageData() async -> Data? {
        await withCheckedContinuation { continuation in
            _ = loadDataRepresentation(for: .image) { data, _ in continuation.resume(returning: data) }
        }
    }
}
