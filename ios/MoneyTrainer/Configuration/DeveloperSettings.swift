import Foundation
import Observation

/// 開発用の切り替え。ユーザー導線の一等地から外し、設定画面へ隔離する。
@MainActor
@Observable
final class DeveloperSettings {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let mockTrainingKey = "training.mockMode"

    var isMockTrainingEnabled: Bool {
        didSet { defaults.set(isMockTrainingEnabled, forKey: mockTrainingKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isMockTrainingEnabled = defaults.bool(forKey: mockTrainingKey)
    }
}
