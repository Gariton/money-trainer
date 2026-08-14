import Foundation

struct TrainingStartRequest: Encodable, Equatable, Sendable {
    let trainingConfig: [String: String]?
    let mockMode: Bool
}
