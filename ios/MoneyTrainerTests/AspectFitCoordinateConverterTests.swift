import CoreGraphics
import Testing
@testable import MoneyTrainer

@Suite("Aspect-fit coordinate conversion")
struct AspectFitCoordinateConverterTests {
    @Test("Normalized coordinates round-trip through a letterboxed canvas")
    func roundTrip() {
        let converter = AspectFitCoordinateConverter(
            imageSize: CGSize(width: 1_000, height: 500),
            canvasSize: CGSize(width: 400, height: 400)
        )
        let normalized = NormalizedRect(centerX: 0.5, centerY: 0.5, width: 0.2, height: 0.2)

        let display = converter.displayRect(for: normalized)
        #expect(abs(display.minX - 160) < 0.0001)
        #expect(abs(display.minY - 180) < 0.0001)
        #expect(abs(display.width - 80) < 0.0001)
        #expect(abs(display.height - 40) < 0.0001)

        let result = converter.normalizedRect(from: display)
        #expect(abs(result.centerX - normalized.centerX) < 0.0001)
        #expect(abs(result.centerY - normalized.centerY) < 0.0001)
        #expect(abs(result.width - normalized.width) < 0.0001)
        #expect(abs(result.height - normalized.height) < 0.0001)
    }

    @Test("Clamping keeps the full rectangle in the image")
    func clamping() {
        let result = NormalizedRect(centerX: 1.2, centerY: -0.2, width: 0.4, height: 0.3).clamped()
        #expect(result.isValid)
        #expect(abs(result.maxX - 1) < 0.0001)
        #expect(abs(result.minY) < 0.0001)
    }

    @Test("Corner resizing keeps the opposite corner fixed")
    func cornerResizing() {
        let initial = NormalizedRect(
            centerX: 0.5,
            centerY: 0.5,
            width: 0.4,
            height: 0.4
        )

        let result = initial.resized(
            at: .topLeft,
            by: CGSize(width: -0.1, height: 0.05)
        )

        #expect(abs(result.minX - 0.2) < 0.0001)
        #expect(abs(result.minY - 0.35) < 0.0001)
        #expect(abs(result.maxX - initial.maxX) < 0.0001)
        #expect(abs(result.maxY - initial.maxY) < 0.0001)
        #expect(result.isValid)
    }

    @Test("Corner resizing clamps the dragged edges without shifting the opposite edges")
    func cornerResizeClamping() {
        let initial = NormalizedRect(
            centerX: 0.5,
            centerY: 0.5,
            width: 0.4,
            height: 0.4
        )

        let result = initial.resized(
            at: .bottomRight,
            by: CGSize(width: 1, height: -1),
            minimumSize: 0.05
        )

        #expect(abs(result.minX - initial.minX) < 0.0001)
        #expect(abs(result.minY - initial.minY) < 0.0001)
        #expect(abs(result.maxX - 1) < 0.0001)
        #expect(abs(result.maxY - (initial.minY + 0.05)) < 0.0001)
        #expect(result.isValid)
    }

    @Test("Viewport zoom converts screen drag distance at the visual scale")
    func zoomedTranslation() {
        let converter = AspectFitCoordinateConverter(
            imageSize: CGSize(width: 1_000, height: 500),
            canvasSize: CGSize(width: 400, height: 400)
        )

        let translation = converter.normalizedTranslation(
            for: CGSize(width: 80, height: 40),
            viewportScale: 4
        )

        #expect(abs(translation.width - 0.05) < 0.0001)
        #expect(abs(translation.height - 0.05) < 0.0001)
    }
}
