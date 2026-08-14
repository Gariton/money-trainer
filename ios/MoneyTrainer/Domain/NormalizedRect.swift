import CoreGraphics
import Foundation

struct NormalizedRect: Codable, Equatable, Hashable, Sendable {
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double

    static let centeredDefault = NormalizedRect(
        centerX: 0.5,
        centerY: 0.5,
        width: 0.24,
        height: 0.24
    )

    var isValid: Bool {
        let values = [centerX, centerY, width, height]
        return values.allSatisfy(\.isFinite)
            && width > 0
            && height > 0
            && minX >= 0
            && minY >= 0
            && maxX <= 1
            && maxY <= 1
    }

    var minX: Double { centerX - width / 2 }
    var minY: Double { centerY - height / 2 }
    var maxX: Double { centerX + width / 2 }
    var maxY: Double { centerY + height / 2 }

    func clamped(minimumSize: Double = 0.015) -> NormalizedRect {
        let clampedWidth = min(max(width, minimumSize), 1)
        let clampedHeight = min(max(height, minimumSize), 1)
        return NormalizedRect(
            centerX: min(max(centerX, clampedWidth / 2), 1 - clampedWidth / 2),
            centerY: min(max(centerY, clampedHeight / 2), 1 - clampedHeight / 2),
            width: clampedWidth,
            height: clampedHeight
        )
    }
}
