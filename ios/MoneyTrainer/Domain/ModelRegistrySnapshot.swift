import Foundation

struct ModelRegistrySnapshot: Codable, Equatable, Sendable {
    var models: [LocalModelRecord]
    var activeModelID: String?

    private enum CodingKeys: String, CodingKey {
        case models
        case activeModelID = "active_model_id"
    }

    static let empty = ModelRegistrySnapshot(models: [], activeModelID: nil)
}
