import Foundation

struct ServerValidationDetail: Decodable, Sendable {
    let code: String
    let errors: [TrainingValidationIssue]
}
