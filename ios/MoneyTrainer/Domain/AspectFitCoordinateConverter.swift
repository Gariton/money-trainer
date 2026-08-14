import CoreGraphics
import Foundation

struct AspectFitCoordinateConverter: Equatable, Sendable {
    let imageSize: CGSize
    let canvasSize: CGSize

    var imageFrame: CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return .zero
        }

        let scale = min(
            canvasSize.width / imageSize.width,
            canvasSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: (canvasSize.width - fittedSize.width) / 2,
            y: (canvasSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func displayRect(for normalizedRect: NormalizedRect) -> CGRect {
        let frame = imageFrame
        return CGRect(
            x: frame.minX + normalizedRect.minX * frame.width,
            y: frame.minY + normalizedRect.minY * frame.height,
            width: normalizedRect.width * frame.width,
            height: normalizedRect.height * frame.height
        )
    }

    func normalizedRect(from displayRect: CGRect) -> NormalizedRect {
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else { return .centeredDefault }

        return NormalizedRect(
            centerX: (displayRect.midX - frame.minX) / frame.width,
            centerY: (displayRect.midY - frame.minY) / frame.height,
            width: displayRect.width / frame.width,
            height: displayRect.height / frame.height
        ).clamped()
    }

    func normalizedTranslation(for displayTranslation: CGSize) -> CGSize {
        let frame = imageFrame
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGSize(
            width: displayTranslation.width / frame.width,
            height: displayTranslation.height / frame.height
        )
    }
}
