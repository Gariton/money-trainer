import Foundation

enum AppTab: Hashable, CaseIterable {
    case dataset
    case training
    case models
    case liveTest
    case settings

    /// パイプラインの順番 (集める → 学習する → 配る → 試す) をそのままタブ順にする。
    var title: String {
        switch self {
        case .dataset: "データ"
        case .training: "学習"
        case .models: "モデル"
        case .liveTest: "テスト"
        case .settings: "設定"
        }
    }

    var symbolName: String {
        switch self {
        case .dataset: "photo.stack"
        case .training: "bolt.horizontal.circle"
        case .models: "shippingbox"
        case .liveTest: "viewfinder"
        case .settings: "gearshape"
        }
    }
}
