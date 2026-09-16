import Foundation
import Security

/// Keychain storage for the OpenAI credential, shared between the app and the
/// keyboard extension.
///
/// WHY THE KEYCHAIN AND NOWHERE ELSE. The brief forbids the key in source, in
/// Info.plist, in an xcconfig, in UserDefaults, in App Group defaults, in a
/// bundled resource and in anything compiled into the IPA. Every one of those
/// prohibitions still holds in this build: the key is typed by the user at
/// runtime, on device, and only ever exists in the keychain item below. A build
/// of this project contains no credential, so distributing the IPA distributes
/// no secret.
///
/// What this does NOT claim: the keychain is not a vault against someone
/// holding the unlocked device. It is device-only (never synced to iCloud) and
/// unreadable by other apps, which is the right protection for a key the user
/// themselves entered.
enum SecureCredentialStore {

    /// App Group identifiers are usable as keychain access groups on iOS with no
    /// additional entitlement, which is what lets the keyboard read what the
    /// app wrote.
    private static let accessGroup = AppGroup.identifier
    private static let service = "kz.yerek.replykeyboard.openai"
    private static let account = "openai.api.key"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    /// Reads the stored key, or nil when none has been entered.
    static func apiKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static var hasAPIKey: Bool { apiKey() != nil }

    /// Stores or replaces the key. Returns false when the keychain refused,
    /// which is reported to the user rather than silently swallowed.
    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteAPIKey() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // After-first-unlock so the keyboard can read it while the device is
            // in use; ThisDeviceOnly so it is never carried to another device by
            // iCloud Keychain or a backup.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insert = query
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteAPIKey() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Backend token

    private static let tokenAccount = "backend.client.token"

    private static func tokenQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    /// Bearer token for the optional backend transport. Same storage rules.
    static func backendToken() -> String? {
        var query = tokenQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    static func setBackendToken(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else {
            let status = SecItemDelete(tokenQuery() as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard let data = token.data(using: .utf8) else { return false }
        let query = tokenQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }
        var insert = query
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}
