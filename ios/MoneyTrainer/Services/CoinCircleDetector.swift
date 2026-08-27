import CoreGraphics
import Foundation
import ImageIO
import Vision

struct CoinCircleDetector: CoinCircleDetecting, Sendable {
    static let maximumCandidateCount = 40

    func detect(in imageData: Data) async throws -> [NormalizedRect] {
        guard let imageProperties = Self.imageProperties(from: imageData) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var darkOnLightRequest = DetectContoursRequest()
        darkOnLightRequest.contrastAdjustment = 1
        darkOnLightRequest.detectsDarkOnLight = true
        darkOnLightRequest.maximumImageDimension = 1_024

        var lightOnDarkRequest = DetectContoursRequest()
        lightOnDarkRequest.contrastAdjustment = 1
        lightOnDarkRequest.detectsDarkOnLight = false
        lightOnDarkRequest.maximumImageDimension = 1_024

        let darkOnLightObservation = try await darkOnLightRequest.perform(
            on: imageData,
            orientation: imageProperties.orientation
        )
        let lightOnDarkObservation = try await lightOnDarkRequest.perform(
            on: imageData,
            orientation: imageProperties.orientation
        )
        let observations = [darkOnLightObservation, lightOnDarkObservation]

        let candidates = observations.flatMap {
            Self.candidates(from: $0, imageAspectRatio: imageProperties.aspectRatio)
        }
        return Self.selectDistinctRects(from: candidates)
    }

    static func candidate(
        boundingBox: CGRect,
        circularity: Double,
        imageAspectRatio: Double,
        polygonPointCount: Int
    ) -> (rect: NormalizedRect, score: Double)? {
        let width = Double(boundingBox.width)
        let height = Double(boundingBox.height)
        guard isPlausibleBoundingBox(boundingBox) else { return nil }

        let physicalAspectRatio = width * imageAspectRatio / height
        guard physicalAspectRatio > 0 else { return nil }
        let aspectRatio = min(physicalAspectRatio, 1 / physicalAspectRatio)
        guard aspectRatio >= 0.68,
              circularity >= 0.70,
              polygonPointCount >= 6 else {
            return nil
        }

        let paddedWidth = min(width * 1.06, 1)
        let paddedHeight = min(height * 1.06, 1)
        let rect = NormalizedRect(
            centerX: Double(boundingBox.midX),
            centerY: 1 - Double(boundingBox.midY),
            width: paddedWidth,
            height: paddedHeight
        ).clamped()
        let pointScore = min(Double(polygonPointCount) / 12, 1)
        let score = min(circularity, 1) * 0.55 + aspectRatio * 0.25 + pointScore * 0.20
        return (rect, score)
    }

    static func selectDistinctRects(
        from candidates: [(rect: NormalizedRect, score: Double)],
        maximumCount: Int = maximumCandidateCount
    ) -> [NormalizedRect] {
        var selected: [NormalizedRect] = []

        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard !selected.contains(where: {
                $0.intersectionOverUnion(with: candidate.rect) >= 0.55
                    || $0.intersectionOverSmallerRect(with: candidate.rect) >= 0.78
            }) else {
                continue
            }
            selected.append(candidate.rect)
            if selected.count == maximumCount { break }
        }

        return selected.sorted {
            if abs($0.centerY - $1.centerY) > 0.02 {
                return $0.centerY < $1.centerY
            }
            return $0.centerX < $1.centerX
        }
    }

    private static func candidates(
        from observation: ContoursObservation,
        imageAspectRatio: Double
    ) -> [(rect: NormalizedRect, score: Double)] {
        let contours = (0..<observation.contourCount).compactMap(observation.contourAtIndex)

        return contours.compactMap { contour in
            let boundingBox = contour.normalizedPath.boundingBoxOfPath
            guard isPlausibleBoundingBox(boundingBox) else { return nil }
            let polygonPointCount = (try? contour.polygonApproximation(epsilon: 0.005).pointCount)
                ?? contour.pointCount
            return candidate(
                boundingBox: boundingBox,
                circularity: circularity(
                    points: contour.normalizedPoints,
                    imageAspectRatio: imageAspectRatio
                ),
                imageAspectRatio: imageAspectRatio,
                polygonPointCount: polygonPointCount
            )
        }
    }

    private static func imageProperties(
        from imageData: Data
    ) -> (aspectRatio: Double, orientation: CGImagePropertyOrientation)? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              pixelWidth.doubleValue > 0,
              pixelHeight.doubleValue > 0 else {
            return nil
        }

        let orientationRawValue = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRawValue) ?? .up
        let isRotated = switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: true
        default: false
        }
        let width = isRotated ? pixelHeight.doubleValue : pixelWidth.doubleValue
        let height = isRotated ? pixelWidth.doubleValue : pixelHeight.doubleValue
        return (width / height, orientation)
    }

    private static func isPlausibleBoundingBox(_ boundingBox: CGRect) -> Bool {
        let width = Double(boundingBox.width)
        let height = Double(boundingBox.height)
        return width >= 0.04
            && height >= 0.04
            && width <= 0.70
            && height <= 0.70
            && width * height >= 0.002
    }

    private static func circularity(
        points: [SIMD2<Float>],
        imageAspectRatio: Double
    ) -> Double {
        guard points.count >= 3 else { return 0 }
        var twiceArea = 0.0
        var perimeter = 0.0

        for index in points.indices {
            let nextIndex = points.index(after: index) == points.endIndex
                ? points.startIndex
                : points.index(after: index)
            let currentX = Double(points[index].x) * imageAspectRatio
            let currentY = Double(points[index].y)
            let nextX = Double(points[nextIndex].x) * imageAspectRatio
            let nextY = Double(points[nextIndex].y)
            twiceArea += currentX * nextY - nextX * currentY
            perimeter += hypot(nextX - currentX, nextY - currentY)
        }

        guard perimeter > 0 else { return 0 }
        let area = abs(twiceArea) / 2
        return 4 * Double.pi * area / (perimeter * perimeter)
    }
}
