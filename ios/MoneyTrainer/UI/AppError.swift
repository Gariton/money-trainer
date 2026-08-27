import Foundation

/// 失敗の種類を分けて、回復手段まで含めて提示するためのモデル。
/// 「OKだけのアラート」をやめ、原因に応じた次の一手を出すために使う。
struct AppError: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// サーバーへ到達できない。
        case connection
        /// 認証に失敗した。Tokenの問題。
        case authentication
        /// 入力またはリクエストが不正。
        case validation
        /// サーバー側の障害。
        case server
        /// 分類できない失敗。
        case unknown
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String

    init(id: UUID = UUID(), kind: Kind, title: String, message: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }

    init(_ error: any Error, title: String? = nil) {
        let resolved = Self.classify(error)
        self.init(
            kind: resolved.kind,
            title: title ?? resolved.title,
            message: resolved.message
        )
    }

    /// 再試行で解決する見込みがあるか。
    var isRetryable: Bool {
        switch kind {
        case .connection, .server, .unknown: true
        case .authentication, .validation: false
        }
    }

    /// 設定画面へ誘導すべきか。
    var suggestsConfiguration: Bool {
        kind == .connection || kind == .authentication
    }

    var symbolName: String {
        switch kind {
        case .connection: "wifi.exclamationmark"
        case .authentication: "key.slash"
        case .validation: "exclamationmark.triangle"
        case .server: "exclamationmark.icloud"
        case .unknown: "exclamationmark.circle"
        }
    }

    var recoveryHint: String {
        switch kind {
        case .connection:
            "Macでサーバーが起動しているか、設定のBase URLが正しいか確認してください。"
        case .authentication:
            "設定のBearer tokenがサーバーの API_TOKEN と一致しているか確認してください。"
        case .validation:
            "入力内容を見直してから、もう一度実行してください。"
        case .server:
            "サーバー側のログを確認してください。時間をおくと復旧する場合があります。"
        case .unknown:
            "同じ操作を繰り返しても直らない場合は、サーバーのログを確認してください。"
        }
    }

    private static func classify(
        _ error: any Error
    ) -> (kind: Kind, title: String, message: String) {
        guard let apiError = error as? APIError else {
            return (.unknown, "エラーが発生しました", error.localizedDescription)
        }

        switch apiError {
        case .invalidBaseURL:
            return (.connection, "API URLが不正です", "設定のBase URLを確認してください。")
        case .invalidResponse:
            return (.server, "応答が不正です", "サーバーから想定外の応答を受信しました。")
        case let .transport(message):
            return (.connection, "サーバーへ接続できません", message)
        case let .server(statusCode, message) where statusCode == 401 || statusCode == 403:
            return (.authentication, "認証に失敗しました", message)
        case let .server(statusCode, message) where (400..<500).contains(statusCode):
            return (.validation, "リクエストが受け付けられません", message)
        case let .server(statusCode, message):
            return (.server, "サーバーエラー (\(statusCode))", message)
        case let .decoding(message):
            return (.server, "応答を読み取れません", message)
        case let .encoding(message):
            return (.validation, "リクエストを作成できません", message)
        }
    }
}
