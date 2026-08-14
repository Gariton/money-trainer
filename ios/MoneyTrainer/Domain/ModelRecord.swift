import Foundation

struct ModelRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let modelVersion: String
    let createdAt: Date
    let datasetVersion: String
    let metrics: ModelMetrics?
    let coreMLAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case modelVersion = "model_version"
        case createdAt = "created_at"
        case datasetVersion = "dataset_version"
        case metrics
        case coreMLAvailable = "core_ml_available"
    }
}
