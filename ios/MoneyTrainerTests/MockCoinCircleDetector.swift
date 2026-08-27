import Foundation
@testable import MoneyTrainer

struct MockCoinCircleDetector: CoinCircleDetecting {
    let rects: [NormalizedRect]

    func detect(in imageData: Data) async throws -> [NormalizedRect] {
        rects
    }
}
