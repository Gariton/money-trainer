import Foundation
import Observation

@MainActor
@Observable
final class APIConfigurationStore {
    var baseURLText: String
    var token: String
    var error: AppError?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tokenStore: SecureTokenStore
    @ObservationIgnored private let baseURLKey = "api.baseURL"

    init(defaults: UserDefaults = .standard, tokenStore: SecureTokenStore = SecureTokenStore()) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        baseURLText = defaults.string(forKey: baseURLKey) ?? APIConfiguration.defaultBaseURL.absoluteString
        token = tokenStore.load() ?? ""
    }

    var configuration: APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: baseURLText) ?? APIConfiguration.defaultBaseURL,
            token: token.isEmpty ? nil : token
        )
    }

    func persist() -> Bool {
        guard let url = URL(string: baseURLText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            error = AppError(
                kind: .validation,
                title: "API URLが不正です",
                message: "http または https から始まる有効なURLを入力してください。"
            )
            return false
        }
        defaults.set(url.absoluteString, forKey: baseURLKey)
        do {
            try tokenStore.save(token)
            error = nil
            return true
        } catch {
            self.error = AppError(error, title: "設定を保存できません")
            return false
        }
    }

    func clearError() {
        error = nil
    }
}
