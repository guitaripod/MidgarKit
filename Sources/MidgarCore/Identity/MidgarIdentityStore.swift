import Foundation

/// The JSON values of the two identity items on top of a ``MidgarKeychain``.
struct MidgarIdentityStore: Sendable {
    let keychain: any MidgarKeychain
    let appID: String

    private var sessionSlot: MidgarKeychainSlot { .session(appID: appID) }

    /// The shared item. An item that exists but cannot be decoded is never overwritten, because a newer MidgarKit may have written it.
    func readShared() throws -> SharedIdentity? {
        guard let data = try keychain.read(.shared) else {
            return nil
        }
        guard let shared = try? JSONDecoder().decode(SharedIdentity.self, from: data) else {
            throw MidgarIdentityError.corruptSharedItem
        }
        return shared
    }

    func writeShared(_ shared: SharedIdentity) throws {
        try keychain.write(try encode(shared), to: .shared)
    }

    /// Writes the shared item only when no app has written one yet.
    func writeSharedIfAbsent(_ shared: SharedIdentity) throws -> Bool {
        try keychain.writeIfAbsent(try encode(shared), to: .shared)
    }

    func deleteShared() throws {
        try keychain.delete(.shared)
    }

    /// The per-app item. One that cannot be decoded is removed: it holds nothing the server cannot reissue through an attach.
    func readSession() throws -> StoredSession? {
        guard let data = try keychain.read(sessionSlot) else {
            return nil
        }
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            try keychain.delete(sessionSlot)
            return nil
        }
        return session
    }

    func writeSession(_ session: StoredSession) throws {
        try keychain.write(try encode(session), to: sessionSlot)
    }

    func deleteSession() throws {
        try keychain.delete(sessionSlot)
    }

    private func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw MidgarIdentityError.malformedResponse
        }
    }
}
