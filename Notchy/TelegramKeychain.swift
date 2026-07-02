import Foundation
import Security

/// Stores the Telegram bot token — the one secret this feature needs.
/// Device-only, no iCloud sync: this credential grants remote control of the
/// user's terminal, so it must never leave the Mac via Keychain sync.
enum TelegramKeychain {
    private static let service = "com.notchly.telegram"
    private static let account = "botToken"

    private static func query() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        delete()
        var attributes = query()
        attributes[kSecValueData] = Data(token.utf8)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        var attributes = query()
        attributes[kSecReturnData] = true
        attributes[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(query() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
