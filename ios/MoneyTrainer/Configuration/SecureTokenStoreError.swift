import Foundation
import Security

enum SecureTokenStoreError: LocalizedError, Sendable {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status): "API tokenを保存できませんでした (\(status))。"
        }
    }
}
