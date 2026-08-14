import Foundation
import Observation

@MainActor
@Observable
final class APIConfigurationStore {
    var baseURLText: String
    var token: String
    var errorMessage: String?
    var isShowingError = false

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
            errorMessage = "http または https の有効なAPI URLを入力してください。"
            isShowingError = true
            return false
        }
        defaults.set(url.absoluteString, forKey: baseURLKey)
        do {
            try tokenStore.save(token)
            errorMessage = nil
            isShowingError = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
            return false
        }
    }

    func clearError() {
        isShowingError = false
        errorMessage = nil
    }
}
