import Foundation
import Security


struct KeychainStore {
    private let service = "com.kakitangan.leave-notifier"

    func hasPassword(account: String) -> Bool {
        hasSecret(account: account)
    }

    func password(account: String) throws -> String {
        do {
            return try secret(account: account)
        } catch NotifierError.secretNotConfigured {
            throw NotifierError.passwordNotConfigured
        }
    }

    func save(password: String, account: String) throws {
        guard !password.isEmpty else {
            throw NotifierError.passwordNotConfigured
        }
        try save(secret: password, account: account)
    }

    func hasSecret(account: String) -> Bool {
        guard !account.isEmpty else {
            return false
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func secret(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw NotifierError.secretNotConfigured
        }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw NotifierError.keychainAccessFailed(status: status)
        }
        return value
    }

    func save(secret: String, account: String) throws {
        guard !secret.isEmpty else {
            throw NotifierError.secretNotConfigured
        }
        let secretData = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes = [kSecValueData as String: secretData]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw NotifierError.keychainAccessFailed(status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = secretData
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NotifierError.keychainAccessFailed(status: addStatus)
        }
    }

    func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NotifierError.keychainAccessFailed(status: status)
        }
    }
}
