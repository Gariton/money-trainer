import Foundation

struct InferenceResponse: Codable, Equatable, Sendable {
    let modelID: String?
    let modelVersion: String?
    let annotations: [Annotation]

    private enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case modelVersion = "model_version"
        case annotations
    }
}
