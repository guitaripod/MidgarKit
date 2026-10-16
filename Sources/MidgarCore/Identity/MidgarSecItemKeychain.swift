import Foundation
#if canImport(Security)
import Security

/// The Security framework keychain behind the identity flows.
///
/// The shared slot is a synchronizable generic password in the team access group, readable after first unlock. The session slot is a device-only generic password with no access group. On macOS both use the data protection keychain.
public struct MidgarSecItemKeychain: MidgarKeychain {
    public let accessGroup: String?

    /// - Parameter accessGroup: The shared item's keychain access group, prefixed with the team id. Pass nil where the app has no such entitlement, for example in unit tests.
    public init(accessGroup: String? = MidgarKeychainLayout.defaultAccessGroup) {
        self.accessGroup = accessGroup
    }

    public func read(_ slot: MidgarKeychainSlot) throws -> Data? {
        var query = identifyingQuery(for: slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw MidgarKeychainError(status: errSecDecode)
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw MidgarKeychainError(status: status)
        }
    }

    public func write(_ data: Data, to slot: MidgarKeychainSlot) throws {
        let status = SecItemAdd(creationAttributes(for: slot, data: data) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(identifyingQuery(for: slot) as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw MidgarKeychainError(status: updateStatus)
            }
        default:
            throw MidgarKeychainError(status: status)
        }
    }

    public func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool {
        let status = SecItemAdd(creationAttributes(for: slot, data: data) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecDuplicateItem:
            return false
        default:
            throw MidgarKeychainError(status: status)
        }
    }

    public func delete(_ slot: MidgarKeychainSlot) throws {
        let status = SecItemDelete(identifyingQuery(for: slot) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MidgarKeychainError(status: status)
        }
    }

    /// The attributes that select the slot's item.
    func identifyingQuery(for slot: MidgarKeychainSlot) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        switch slot {
        case .shared:
            query[kSecAttrService as String] = MidgarKeychainLayout.sharedService
            query[kSecAttrAccount as String] = MidgarKeychainLayout.sharedAccount
            query[kSecAttrSynchronizable as String] = true
            if let accessGroup {
                query[kSecAttrAccessGroup as String] = accessGroup
            }
        case .session(let appID):
            query[kSecAttrService as String] = MidgarKeychainLayout.sessionService
            query[kSecAttrAccount as String] = appID
            query[kSecAttrSynchronizable as String] = false
        case .local(let appID):
            query[kSecAttrService as String] = MidgarKeychainLayout.localService
            query[kSecAttrAccount as String] = appID
            query[kSecAttrSynchronizable as String] = false
        }
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    /// The selecting attributes plus the value and the accessibility class the slot is created with.
    func creationAttributes(for slot: MidgarKeychainSlot, data: Data) -> [String: Any] {
        var attributes = identifyingQuery(for: slot)
        attributes[kSecValueData as String] = data
        switch slot {
        case .shared:
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        case .session, .local:
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return attributes
    }
}
#endif
