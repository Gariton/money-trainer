import Foundation

struct TrainingValidationIssue: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let message: String

    var id: String { "\(code):\(message)" }
}
