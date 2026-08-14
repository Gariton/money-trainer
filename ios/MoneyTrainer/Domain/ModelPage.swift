import Foundation

struct ModelPage: Codable, Equatable, Sendable {
    let items: [ModelRecord]
    let total: Int
    let limit: Int?
    let offset: Int?
}
