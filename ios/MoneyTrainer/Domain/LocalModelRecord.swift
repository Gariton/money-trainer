import Foundation

struct LocalModelRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let modelVersion: String
    let installedAt: Date
    let compiledPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case modelVersion = "model_version"
        case installedAt = "installed_at"
        case compiledPath = "compiled_path"
    }
}
