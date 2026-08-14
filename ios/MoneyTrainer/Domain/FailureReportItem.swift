import Foundation

struct FailureReportItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    let category: String
    let path: String
    let contentType: String
    let url: String

    var id: String { path }

    var categoryDisplayName: String {
        category.replacing("_", with: " ").capitalized
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case path
        case contentType = "content_type"
        case url
    }
}
