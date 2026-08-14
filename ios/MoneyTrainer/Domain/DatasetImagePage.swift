import Foundation

struct DatasetImagePage: Codable, Equatable, Sendable {
    let items: [DatasetImageRecord]
    let total: Int
    let limit: Int
    let offset: Int
}
