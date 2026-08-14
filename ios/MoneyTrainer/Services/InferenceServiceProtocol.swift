import Foundation

protocol InferenceServiceProtocol: Sendable {
    func infer(imageData: Data) async throws -> InferenceResponse
}
