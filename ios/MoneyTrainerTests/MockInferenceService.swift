import Foundation
@testable import MoneyTrainer

struct MockInferenceService: InferenceServiceProtocol {
    let response: InferenceResponse

    func infer(imageData: Data) async throws -> InferenceResponse { response }
}
