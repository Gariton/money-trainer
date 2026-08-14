import Foundation

struct APIConfiguration: Equatable, Sendable {
    var baseURL: URL
    var token: String?

    static let defaultBaseURL = URL(string: "http://127.0.0.1:8000")
        ?? URL(filePath: "/")
}
