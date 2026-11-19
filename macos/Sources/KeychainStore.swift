import Foundation
import Security

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "无法访问系统钥匙串：\(message)（\(status)）"
        }
    }
}

/// Stores SMTP passwords in the macOS Keychain, never in UserDefaults or on disk.
enum KeychainStore {
    private static let service = "com.beibei.oneclickmail.smtp"

    private static func account(for email: String) -> String {
        "smtp:" + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func baseQuery(for email: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: email)
        ]
    }

    static func save(_ password: String, for email: String) throws {
        let data = Data(password.utf8)
        let query = baseQuery(for: email)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unhandled(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unhandled(addStatus)
        }
    }

    static func password(for email: String) -> String? {
        var query = baseQuery(for: email)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasPassword(for email: String) -> Bool {
        guard let password = password(for: email) else { return false }
        return !password.isEmpty
    }

    static func delete(for email: String) {
        SecItemDelete(baseQuery(for: email) as CFDictionary)
    }
}
