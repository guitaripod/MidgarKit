import Foundation

/// The outcome of ``MidgarIdentity/linkApple(identityToken:)``.
public struct MidgarAppleLinkResult: Sendable, Equatable {
    public let midgarId: String
    public let merged: Bool
}

private let staleTokenCodes: Set<String> = ["token_expired", "invalid_token", "identity_merged"]

extension MidgarIdentity {
    /// Links a Sign in with Apple account to this Midgar ID. When the Apple account already belongs to another ID, the service merges this one into it; the shared item then takes the surviving ID and its rotated credential and this session adopts the new tokens.
    @discardableResult
    public func linkApple(identityToken: String) async throws -> MidgarAppleLinkResult {
        try await normalized {
            let reply: LinkAppleReply = try await withBearer { token in
                try await self.post("link/apple", LinkAppleBody(identityToken: identityToken), bearer: token)
            }
            guard reply.merged else {
                return MidgarAppleLinkResult(midgarId: reply.midgarId, merged: false)
            }
            try adoptMerge(reply)
            return MidgarAppleLinkResult(midgarId: reply.midgarId, merged: true)
        }
    }

    /// Deletes the identity on the server, then removes both keychain items, so no app of this Apple Account keeps a credential for it. Without any stored identity there is nothing to delete.
    public func deleteIdentity() async throws {
        try await normalized {
            guard try store.readShared() != nil || store.readSession() != nil else {
                log.info("identity: nothing to delete")
                return
            }
            try await withBearer { token in
                _ = try await self.http.sendRaw(self.request("me", method: .delete, bearer: token))
            }
            dropCachedSession()
            try clearKeychainAfterDeletion()
            log.info("identity: deleted")
        }
    }

    /// Everything the service stores about this identity, as the service's raw JSON.
    public func export() async throws -> Data {
        try await normalized {
            try await withBearer { token in
                let (data, _) = try await self.http.sendRaw(self.request("me/export", method: .get, bearer: token))
                return data
            }
        }
    }

    /// Runs a bearer call with the current access token. A token the service no longer accepts (expired, signed with a rotated key, or issued for an ID that was merged since) is dropped and the call repeats once with a fresh one.
    private func withBearer<Value: Sendable>(_ call: (String) async throws -> Value) async throws -> Value {
        do {
            return try await call(try await accessToken())
        } catch let error as MidgarHTTPError {
            guard let code = error.serverCode, staleTokenCodes.contains(code) else {
                throw error
            }
            log.info("identity: access token rejected (\(code)), refreshing and retrying once")
            dropCachedSession()
            return try await call(try await accessToken())
        }
    }

    /// Step 5 of Sign in with Apple: overwrites the shared item with the survivor's ID and rotated credential, then stores the new refresh token. The merged session keeps the key of the session that linked.
    private func adoptMerge(_ reply: LinkAppleReply) throws {
        guard let accessToken = reply.accessToken, let refreshToken = reply.refreshToken,
              let credential = reply.credential, let expiresIn = reply.expiresIn
        else {
            throw MidgarIdentityError.malformedResponse
        }
        let previousKey = try store.readSession()?.keyId
        try store.writeShared(SharedIdentity(midgarId: reply.midgarId, credential: credential))
        try store.writeSession(StoredSession(refreshToken: refreshToken, keyId: previousKey, midgarId: reply.midgarId))
        adopt(LiveSession(
            reply: SessionReply(midgarId: reply.midgarId, accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn),
            now: clock()
        ))
        log.info("identity: merged into the Apple account's identity, adopted its ID and credential")
    }

    /// Removes both items even when the first removal fails, then reports the first failure.
    private func clearKeychainAfterDeletion() throws {
        var firstFailure: (any Error)?
        for removal in [store.deleteSession, store.deleteShared] {
            do {
                try removal()
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }
}
