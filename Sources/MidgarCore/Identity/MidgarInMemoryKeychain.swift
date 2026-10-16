import Foundation

/// A keychain that lives in memory: the test double, and the stand-in on platforms without the Security framework. `items` is the only mutable state and is read and written only inside `lock`, which is what makes the unchecked conformance sound.
public final class MidgarInMemoryKeychain: MidgarKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [MidgarKeychainSlot: Data]

    public init(items: [MidgarKeychainSlot: Data] = [:]) {
        self.items = items
    }

    public func read(_ slot: MidgarKeychainSlot) throws -> Data? {
        lock.withLock { items[slot] }
    }

    public func write(_ data: Data, to slot: MidgarKeychainSlot) throws {
        lock.withLock { items[slot] = data }
    }

    public func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool {
        lock.withLock {
            guard items[slot] == nil else {
                return false
            }
            items[slot] = data
            return true
        }
    }

    public func delete(_ slot: MidgarKeychainSlot) throws {
        lock.withLock { items[slot] = nil }
    }
}
