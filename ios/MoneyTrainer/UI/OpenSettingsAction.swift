import SwiftUI

/// どの画面からでも設定タブへ移動するための共通アクション。
/// 接続エラーの回復導線を各画面へ配るために使う。
struct OpenSettingsAction {
    let handler: () -> Void

    func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    @Entry var openSettings = OpenSettingsAction(handler: {})
}
