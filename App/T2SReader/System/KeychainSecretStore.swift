import Foundation
import Security
import T2SApp

/// Host-only storage for the BYO cloud voice key. It intentionally has no UserDefaults fallback,
/// no extension dependency, and returns only a safe status error to the UI.
final class KeychainSecretStore: SecretStoring, @unchecked Sendable {
    private let service = "com.t2s.reader.cloud-voice"
    private let account = "default"

    func save(_ value: String) throws {
        let query = baseQuery
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainSecretStoreError.status(status) }
            return
        }

        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainSecretStoreError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainSecretStoreError.status(status)
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw KeychainSecretStoreError.status(status) }
        return value
    }

    private var baseQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }
}

private enum KeychainSecretStoreError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        "The API key could not be stored securely. Check that Keychain is available and try again."
    }
}
