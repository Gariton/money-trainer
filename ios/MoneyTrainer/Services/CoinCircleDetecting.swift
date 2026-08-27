import Foundation

protocol CoinCircleDetecting: Sendable {
    func detect(in imageData: Data) async throws -> [NormalizedRect]
}
