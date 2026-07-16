import Foundation
import Security


struct KeychainStore {
    private let service = "com.kakitangan.leave-notifier"

    func hasPassword(account: String) -> Bool {
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

    func password(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
            throw NotifierError.passwordNotConfigured
        }
        return password
    }

    func save(password: String, account: String) throws {
        guard !password.isEmpty else {
            throw NotifierError.passwordNotConfigured
        }
        let passwordData = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes = [kSecValueData as String: passwordData]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw NotifierError.passwordNotConfigured
        }

        var addQuery = query
        addQuery[kSecValueData as String] = passwordData
        guard SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess else {
            throw NotifierError.passwordNotConfigured
        }
    }
}
