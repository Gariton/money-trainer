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

    func intersectionOverUnion(with other: NormalizedRect) -> Double {
        let intersection = intersectionArea(with: other)
        let union = width * height + other.width * other.height - intersection
        guard union > 0 else { return 0 }
        return intersection / union
    }

    func intersectionOverSmallerRect(with other: NormalizedRect) -> Double {
        let smallerArea = min(width * height, other.width * other.height)
        guard smallerArea > 0 else { return 0 }
        return intersectionArea(with: other) / smallerArea
    }

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

    func resized(
        at handle: BoundingBoxResizeHandle,
        by normalizedTranslation: CGSize,
        minimumSize: Double = 0.015
    ) -> NormalizedRect {
        let initial = clamped(minimumSize: minimumSize)
        let deltaX = Double(normalizedTranslation.width)
        let deltaY = Double(normalizedTranslation.height)
        var left = initial.minX
        var top = initial.minY
        var right = initial.maxX
        var bottom = initial.maxY

        switch handle {
        case .topLeft:
            left = min(max(left + deltaX, 0), right - minimumSize)
            top = min(max(top + deltaY, 0), bottom - minimumSize)
        case .topRight:
            right = max(min(right + deltaX, 1), left + minimumSize)
            top = min(max(top + deltaY, 0), bottom - minimumSize)
        case .bottomLeft:
            left = min(max(left + deltaX, 0), right - minimumSize)
            bottom = max(min(bottom + deltaY, 1), top + minimumSize)
        case .bottomRight:
            right = max(min(right + deltaX, 1), left + minimumSize)
            bottom = max(min(bottom + deltaY, 1), top + minimumSize)
        }

        return NormalizedRect(
            centerX: (left + right) / 2,
            centerY: (top + bottom) / 2,
            width: right - left,
            height: bottom - top
        )
    }

    private func intersectionArea(with other: NormalizedRect) -> Double {
        let intersectionWidth = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let intersectionHeight = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        return intersectionWidth * intersectionHeight
    }
}
