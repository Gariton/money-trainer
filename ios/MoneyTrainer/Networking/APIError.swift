import Foundation

enum APIError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL
    case invalidResponse
    case transport(String)
    case server(statusCode: Int, message: String)
    case decoding(String)
    case encoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "API URLが正しくありません。"
        case .invalidResponse: "サーバーから不正な応答を受信しました。"
        case let .transport(message): "通信に失敗しました: \(message)"
        case let .server(statusCode, message): "APIエラー (\(statusCode)): \(message)"
        case let .decoding(message): "応答を読み取れませんでした: \(message)"
        case let .encoding(message): "リクエストを作成できませんでした: \(message)"
        }
    }
}
