import Foundation
import Security

/// Minimal Keychain wrapper for storing the OpenRouter API key securely.
/// Falls back to the `OPENROUTER_API_KEY` environment variable when the
/// Keychain has no stored value (useful for CLI / CI usage).
enum Keychain {
    private static let service = "com.scheduled.app"
    private static let account = "OPENROUTER_API_KEY"

    /// Resolved API key: Keychain first, then environment variable.
    static func apiKey() -> String? {
        if let stored = read(), !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
           !env.isEmpty {
            return env
        }
        return nil
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        // Remove any existing item first for a clean upsert.
        SecItemDelete(baseQuery() as CFDictionary)

        var attrs = baseQuery()
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        SecItemDelete(baseQuery() as CFDictionary) == errSecSuccess
    }

    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
