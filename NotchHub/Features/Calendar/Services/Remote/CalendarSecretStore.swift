import Foundation
import Security

/// Storage for secrets (ICS feed URLs, OAuth tokens). Never backed by `UserDefaults`.
protocol CalendarSecretStore: Sendable {
    func secret(for key: String) -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String)
}

enum CalendarSecretStoreError: Error, Equatable {
    case keychain(OSStatus)
}

/// Generic-password Keychain items under one service name, one account per key.
struct KeychainCalendarSecretStore: CalendarSecretStore {
    static let defaultService = "\(AppIdentity.bundleID).calendar"

    let service: String

    init(service: String = Self.defaultService) {
        self.service = service
    }

    func secret(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setSecret(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, update)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw CalendarSecretStoreError.keychain(updateStatus) }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw CalendarSecretStoreError.keychain(addStatus) }
    }

    func removeSecret(for key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
