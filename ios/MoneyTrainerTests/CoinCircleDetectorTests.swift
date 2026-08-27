import CoreGraphics
import Testing
import UIKit
@testable import MoneyTrainer

@Suite("Coin circle detector")
struct CoinCircleDetectorTests {
    @Test("Accepts a circular contour and converts Vision coordinates to upper-left coordinates")
    func acceptsCircularContour() throws {
        let candidate = try #require(
            CoinCircleDetector.candidate(
                boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
                circularity: 1,
                imageAspectRatio: 1,
                polygonPointCount: 12
            )
        )

        #expect(abs(candidate.rect.centerX - 0.3) < 0.0001)
        #expect(abs(candidate.rect.centerY - 0.7) < 0.0001)
        #expect(abs(candidate.rect.width - 0.212) < 0.0001)
        #expect(candidate.rect.isValid)
    }

    @Test("Rejects a square contour")
    func rejectsSquareContour() {
        let candidate = CoinCircleDetector.candidate(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            circularity: Double.pi / 4,
            imageAspectRatio: 1,
            polygonPointCount: 4
        )

        #expect(candidate == nil)
    }

    @Test("Keeps one of overlapping concentric candidates")
    func removesDuplicateCandidates() {
        let outer = NormalizedRect(centerX: 0.3, centerY: 0.3, width: 0.2, height: 0.2)
        let inner = NormalizedRect(centerX: 0.3, centerY: 0.3, width: 0.18, height: 0.18)
        let separate = NormalizedRect(centerX: 0.7, centerY: 0.7, width: 0.2, height: 0.2)

        let result = CoinCircleDetector.selectDistinctRects(
            from: [
                (rect: inner, score: 0.90),
                (rect: outer, score: 0.95),
                (rect: separate, score: 0.92)
            ]
        )

        #expect(result.count == 2)
        #expect(result.contains(outer))
        #expect(result.contains(separate))
    }

    @Test("Detects ten separate circles in one image")
    func detectsMultipleCircles() async throws {
        let imageSize = CGSize(width: 800, height: 600)
        let image = UIGraphicsImageRenderer(size: imageSize).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
            UIColor.black.setFill()
            for row in 0..<2 {
                for column in 0..<5 {
                    let rect = CGRect(
                        x: 55 + column * 150,
                        y: 105 + row * 290,
                        width: 90,
                        height: 90
                    )
                    context.cgContext.fillEllipse(in: rect)
                }
            }
        }
        let imageData = try #require(image.jpegData(compressionQuality: 1))

        let rects = try await CoinCircleDetector().detect(in: imageData)

        #expect(rects.count == 10)
        #expect(rects.allSatisfy { $0.isValid })
    }
}
