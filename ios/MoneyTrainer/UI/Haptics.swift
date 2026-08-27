import UIKit

/// 重要なイベントに触覚を割り当てる。無音・無感触の操作を減らす。
@MainActor
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
