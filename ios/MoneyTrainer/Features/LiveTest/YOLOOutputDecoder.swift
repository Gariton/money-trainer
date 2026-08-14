import CoreML
import Foundation

struct YOLOOutputDecoder: Sendable {
    let confidenceThreshold: Double
    let modelInputSize: Double
    let classOrder: [CoinDenomination]

    init(
        confidenceThreshold: Double = 0.25,
        modelInputSize: Double = 640,
        classOrder: [CoinDenomination] = CoinDenomination.allCases
    ) {
        self.confidenceThreshold = confidenceThreshold
        self.modelInputSize = modelInputSize
        self.classOrder = classOrder
    }

    func decode(_ multiArray: MLMultiArray) -> [Annotation] {
        let dimensions = multiArray.shape.map(\.intValue)
        let rowCount: Int
        let prefix: [Int]
        switch dimensions {
        case let dimensions where dimensions.count == 3 && dimensions[0] == 1 && dimensions[2] == 6:
            rowCount = dimensions[1]
            prefix = [0]
        case let dimensions where dimensions.count == 2 && dimensions[1] == 6:
            rowCount = dimensions[0]
            prefix = []
        default:
            return []
        }

        let rows = (0..<rowCount).map { row in
            (0..<6).map { column in
                let indexes = (prefix + [row, column]).map(NSNumber.init(value:))
                return multiArray[indexes].doubleValue
            }
        }
        return decode(rows: rows)
    }

    func decode(rows: [[Double]]) -> [Annotation] {
        rows.compactMap { row in
            guard row.count == 6,
                  row.allSatisfy(\.isFinite),
                  row[4] >= confidenceThreshold else {
                return nil
            }
            let classIndex = Int(row[5].rounded())
            guard classOrder.indices.contains(classIndex) else { return nil }

            let coordinateScale = row[0...3].contains(where: { abs($0) > 1 })
                ? modelInputSize
                : 1
            let x1 = min(max(row[0] / coordinateScale, 0), 1)
            let y1 = min(max(row[1] / coordinateScale, 0), 1)
            let x2 = min(max(row[2] / coordinateScale, 0), 1)
            let y2 = min(max(row[3] / coordinateScale, 0), 1)
            guard x2 > x1, y2 > y1 else { return nil }

            return Annotation(
                denomination: classOrder[classIndex],
                rect: NormalizedRect(
                    centerX: (x1 + x2) / 2,
                    centerY: (y1 + y2) / 2,
                    width: x2 - x1,
                    height: y2 - y1
                ).clamped(),
                confidence: row[4],
                needsReview: row[4] < DesignTokens.lowConfidenceThreshold
            )
        }
    }
}
