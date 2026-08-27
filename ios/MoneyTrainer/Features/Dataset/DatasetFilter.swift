import Foundation

/// 一覧の絞り込み。要対応の画像へ最短で辿り着くための入口。
enum DatasetFilter: String, CaseIterable, Identifiable {
    case all
    case needsReview
    case reviewed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "すべて"
        case .needsReview: "要確認"
        case .reviewed: "確認済み"
        }
    }

    func matches(_ record: DatasetImageRecord) -> Bool {
        switch self {
        case .all: true
        case .needsReview: record.needsAttention
        case .reviewed: !record.needsAttention
        }
    }
}

extension DatasetImageRecord {
    /// 未レビュー、または低confidence・円形候補が残っている画像。
    var needsAttention: Bool {
        if reviewStatus != .reviewed { return true }
        return annotations.contains {
            $0.requiresReview(threshold: DesignTokens.lowConfidenceThreshold)
        }
    }
}
