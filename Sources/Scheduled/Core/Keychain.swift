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
#if os(macOS)
        return saveViaSecurityTool(value)
#else
        return saveViaKeychainAPI(value)
#endif
    }

    private static func saveViaKeychainAPI(_ value: String) -> Bool {
        let data = Data(value.utf8)
        // Remove any existing item first for a clean upsert.
        SecItemDelete(baseQuery() as CFDictionary)

        var attrs = baseQuery()
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

#if os(macOS)
    /// On macOS the same item is read by both the .app and the CLI shim, which
    /// are ad-hoc signed. Ad-hoc signatures change on every rebuild, so a normal
    /// per-app Keychain ACL makes macOS re-prompt ("Scheduled wants to use your
    /// confidential information …") on essentially every run. Storing via
    /// `security -A` marks the item accessible to any app on this Mac with no
    /// prompt. Trade-off: any process running as you can read the key — fine for
    /// a personal, spend-capped API key. For a signed/notarized build, drop `-A`
    /// and let the stable signature's per-app ACL handle it instead.
    private static func saveViaSecurityTool(_ value: String) -> Bool {
        // Delete any prior item (e.g. one created without -A) for a clean ACL,
        // then re-add. Both run as the `security` tool, so neither prompts.
        runSecurity(["delete-generic-password", "-a", account, "-s", service])
        return runSecurity(["add-generic-password", "-a", account, "-s", service,
                            "-w", value, "-U", "-A"])
    }

    @discardableResult
    private static func runSecurity(_ args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }
#endif

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
