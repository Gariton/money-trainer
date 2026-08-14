import Foundation

struct TrainingJobPage: Codable, Equatable, Sendable {
    let items: [TrainingJob]
    let total: Int
    let limit: Int?
    let offset: Int?
}
