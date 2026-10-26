import Foundation
import Security
import Synchronization

/// One secret per name in the login keychain, as a generic password.
///
/// For the GitHub token, which must not sit in the state file beside the
/// shelf's layout: that file is plain JSON and goes into backups.
///
/// 每个名字每次运行最多读一次钥匙串，之后用内存里的结果：码头是 ad-hoc 签名，
/// 每次更新后读旧项 macOS 都会弹钥匙串授权框，以前每次刷新 GitHub 都重读一遍。
/// 用户点了拒绝也记住，这次运行不再读（`KeychainReadCache`）；重新保存令牌会覆盖。
enum KeychainStore {
    private static let service = "com.docket-zh.app"
    private static let cache = Mutex(KeychainReadCache())

    static func read(_ account: String) -> String? {
        cache.withLock { reads in
            reads.read(account) {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return KeychainRead.classify(status: status, data: result as? Data)
            }.value
        }
    }

    /// 有没有这一项：只问属性不读内容，不会弹钥匙串授权框。读过内容的用读到的结果。
    static func exists(_ account: String) -> Bool {
        if let known = cache.withLock({ $0.cached(account) }) { return known.exists }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    @discardableResult
    static func write(_ value: String, for account: String) -> Bool {
        cache.withLock { reads in
            guard reads.needsWrite(value, for: account) else { return true }
            let data = Data(value.utf8)
            let match: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var add = match
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                status = SecItemAdd(add as CFDictionary, nil)
            }
            reads.wrote(value, for: account, succeeded: status == errSecSuccess)
            return status == errSecSuccess
        }
    }

    static func delete(_ account: String) {
        cache.withLock { reads in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            reads.deleted(account)
        }
    }
}
