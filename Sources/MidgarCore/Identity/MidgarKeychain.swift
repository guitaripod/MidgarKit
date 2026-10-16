import Foundation

/// The keychain items of the Midgar ID (D12): one shared by every Midgar app of an Apple Account, one per app and device, and the app-local stand-in for the shared one that is used when the app lacks the keychain access group entitlement.
public enum MidgarKeychainSlot: Sendable, Hashable {
    case shared
    case session(appID: String)
    case local(appID: String)
}

/// The fixed names of the keychain layout. They are part of the contract between every Midgar app, so they never vary per app.
public enum MidgarKeychainLayout {
    public static let sharedService = "cc.midgarcorp.identity"
    public static let sharedAccount = "midgar-id"
    public static let sessionService = "cc.midgarcorp.identity.session"
    public static let localService = "cc.midgarcorp.identity.local"
    public static let defaultAccessGroup = "P4DQK6SRKR.cc.midgarcorp.shared"
}

/// A keychain call that failed, with the raw `OSStatus`.
public struct MidgarKeychainError: Error, Sendable, Equatable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }
}

/// Where the identity flows keep their two items. The SecItem implementation is ``MidgarSecItemKeychain``; ``MidgarInMemoryKeychain`` is the test double.
public protocol MidgarKeychain: Sendable {
    /// The stored bytes, or nil when the slot is empty.
    func read(_ slot: MidgarKeychainSlot) throws -> Data?

    /// Stores the bytes, replacing what the slot holds.
    func write(_ data: Data, to slot: MidgarKeychainSlot) throws

    /// Stores the bytes only when the slot is empty and reports whether it did.
    func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool

    /// Empties the slot. Deleting an empty slot is not an error.
    func delete(_ slot: MidgarKeychainSlot) throws
}
