import Foundation
import Security

struct SecureTokenStore: Sendable {
    private let service = "dev.moneytrainer.api"
    private let account = "api-token"

    func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String?) throws {
        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(lookup as CFDictionary)
        guard let token, !token.isEmpty else { return }

        var item = lookup
        item[kSecValueData] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureTokenStoreError.unhandledStatus(status)
        }
    }
}
