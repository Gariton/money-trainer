import Foundation

struct APIRequest: Equatable, Sendable {
    var path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?
}
