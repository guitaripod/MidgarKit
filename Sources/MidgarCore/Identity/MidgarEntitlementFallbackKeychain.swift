import Foundation

/// Keeps the identity working in a process that cannot reach the shared keychain access group. When a call on the shared slot fails with `errSecMissingEntitlement`, the shared slot is served from an app-local item for the rest of the run, and the first fallback is reported once. The app then has an identity of its own that is not shared with other Midgar apps until the entitlement is added.
///
/// `usesLocal` is the only mutable state and is read and written only inside `lock`, which is what makes the unchecked conformance sound.
final class MidgarEntitlementFallbackKeychain: MidgarKeychain, @unchecked Sendable {
    static let missingEntitlementStatus: Int32 = -34018

    private let base: any MidgarKeychain
    private let appID: String
    private let onFallback: @Sendable () -> Void
    private let lock = NSLock()
    private var usesLocal = false

    init(base: any MidgarKeychain, appID: String, onFallback: @escaping @Sendable () -> Void) {
        self.base = base
        self.appID = appID
        self.onFallback = onFallback
    }

    func read(_ slot: MidgarKeychainSlot) throws -> Data? {
        try perform(slot) { try base.read($0) }
    }

    func write(_ data: Data, to slot: MidgarKeychainSlot) throws {
        try perform(slot) { try base.write(data, to: $0) }
    }

    func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool {
        try perform(slot) { try base.writeIfAbsent(data, to: $0) }
    }

    func delete(_ slot: MidgarKeychainSlot) throws {
        try perform(slot) { try base.delete($0) }
    }

    /// Runs the operation on the slot, or on the app-local slot once the fallback is on. A missing-entitlement failure on the shared slot turns the fallback on and repeats the operation locally.
    private func perform<Value>(
        _ slot: MidgarKeychainSlot,
        _ operation: (MidgarKeychainSlot) throws -> Value
    ) throws -> Value {
        guard slot == .shared else {
            return try operation(slot)
        }
        if lock.withLock({ usesLocal }) {
            return try operation(.local(appID: appID))
        }
        do {
            return try operation(slot)
        } catch let error as MidgarKeychainError where error.status == Self.missingEntitlementStatus {
            engageFallback()
            return try operation(.local(appID: appID))
        }
    }

    private func engageFallback() {
        let isFirst = lock.withLock {
            let wasOn = usesLocal
            usesLocal = true
            return !wasOn
        }
        if isFirst {
            onFallback()
        }
    }
}
