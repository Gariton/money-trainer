import Foundation

enum ZIPArchiveError: LocalizedError, Sendable {
    case invalidArchive
    case unsupportedFeature(String)
    case unsafePath(String)
    case packageMissing

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "ダウンロードしたモデルZIPが壊れています。"
        case let .unsupportedFeature(feature): "未対応のZIP形式です: \(feature)"
        case let .unsafePath(path): "安全でないZIPパスを拒否しました: \(path)"
        case .packageMissing: "ZIP内にMoneyDetector.mlpackageがありません。"
        }
    }
}
