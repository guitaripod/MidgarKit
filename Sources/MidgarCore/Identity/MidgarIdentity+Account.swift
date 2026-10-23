import Foundation

/// The outcome of ``MidgarIdentity/linkApple(identityToken:with:)``.
public struct MidgarAppleLinkResult: Sendable, Equatable {
    public let midgarId: String
    public let merged: Bool
}

/// The one-time challenge that ties a Sign in with Apple request to the link call that follows it. Put ``nonce`` into `ASAuthorizationAppleIDRequest.nonce` before presenting the sheet, then pass this value, unchanged, together with the identity token to ``MidgarIdentity/linkApple(identityToken:with:)``. A request is good for about five minutes and for one link attempt, whether or not that attempt succeeds.
public struct MidgarAppleLinkRequest: Sendable, Equatable {
    /// The lowercase hex SHA-256 of the challenge, the nonce the identity token must carry.
    public let nonce: String
    let challenge: String
}

private let staleTokenCodes: Set<String> = ["token_expired", "invalid_token", "identity_merged"]

private let deletionDoneCodes: Set<String> = ["identity_not_found"]

/// What proves a change to the account: an App Attest assertion by the session's key, or the ID credential for a session without a key.
private struct AccountProof {
    let assertion: String?
    let clientData: String?
    let credential: String?
}

extension MidgarIdentity {
    /// Step one of linking Sign in with Apple: asks the service for a one-time challenge. Set the returned request's `nonce` on the `ASAuthorizationAppleIDRequest`, run the sheet, then call ``linkApple(identityToken:with:)``.
    public func prepareAppleLink() async throws -> MidgarAppleLinkRequest {
        try await normalized {
            let reply: ChallengeReply = try await self.post("challenge", nil)
            return MidgarAppleLinkRequest(nonce: MidgarDigest.sha256Hex(utf8: reply.challenge), challenge: reply.challenge)
        }
    }

    /// Step two: links the Sign in with Apple account to this Midgar ID, proving the change with the session's App Attest key (an assertion over the challenge) or, for a session without a key, with the ID credential. When the Apple account already belongs to another ID, the service merges this one into it; the shared item then takes the surviving ID and its rotated credential and this session adopts the new tokens.
    ///
    /// The challenge is spent by the attempt, so a failure needs a new ``prepareAppleLink()`` and a new Apple sheet.
    @discardableResult
    public func linkApple(identityToken: String, with request: MidgarAppleLinkRequest) async throws -> MidgarAppleLinkResult {
        try await normalized {
            let token = try await accessToken()
            let proof = try await proof(challenge: request.challenge)
            let reply: LinkAppleReply
            do {
                reply = try await self.post(
                    "link/apple",
                    LinkAppleBody(
                        identityToken: identityToken,
                        challenge: request.challenge,
                        assertion: proof.assertion,
                        credential: proof.credential
                    ),
                    bearer: token
                )
            } catch let error as MidgarHTTPError {
                forgetTokenIfStale(error)
                throw error
            }
            guard reply.merged else {
                return MidgarAppleLinkResult(midgarId: reply.midgarId, merged: false)
            }
            try adoptMerge(reply)
            return MidgarAppleLinkResult(midgarId: reply.midgarId, merged: true)
        }
    }

    /// Deletes the identity on the server, then removes both keychain items, so no app of this Apple Account keeps a credential for it. The call proves itself like a link does. It is sent once and never repeated by the HTTP layer; an answer that is lost leaves a mark in the per-app item, and a later call that finds the identity gone (`identity_not_found`, or `invalid_token` after a send) counts the deletion as done and clears both items. Without any stored identity there is nothing to delete.
    public func deleteIdentity() async throws {
        try await normalized {
            let resuming = try store.readSession()?.deleteSentAt != nil
            guard try store.readShared() != nil || store.readPerApp() != nil else {
                log.info("identity: nothing to delete")
                return
            }
            do {
                try await sendDeletion(resuming: resuming)
            } catch is MidgarIdentityGone {
                log.info("identity: the identity was already gone")
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

    /// Sends `DELETE /me` with a fresh proof each time. A 401 for a stale token repeats once, with a new challenge because the first was spent. An answer that proves the identity is gone ends the loop as done; a rejection leaves the stored session as it was found; a lost answer leaves the mark that a deletion was sent.
    private func sendDeletion(resuming: Bool) async throws {
        var replacedToken = false
        while true {
            let token = try await deletionToken(resuming: resuming)
            let body = try await deletionBody()
            try markDeletionSent()
            do {
                _ = try await http.sendRaw(request("me", method: .delete, body: body, bearer: token, neverRetries: true))
                return
            } catch {
                if isDeletionDone(by: error, afterEarlierSend: resuming) {
                    return
                }
                if !replacedToken, error.serverCode.map(staleTokenCodes.contains) == true {
                    replacedToken = true
                    log.info("identity: access token rejected for the deletion, refreshing and sending it once more")
                    dropCachedSession()
                    continue
                }
                if !resuming, error.wasRejectedByService {
                    try clearDeletionMark()
                }
                throw error
            }
        }
    }

    /// True when the answer shows the identity no longer exists: `identity_not_found` always, `invalid_token` once a deletion has been sent before, since the tokens of a deleted identity are refused.
    private func isDeletionDone(by error: MidgarHTTPError, afterEarlierSend: Bool) -> Bool {
        guard let code = error.serverCode else {
            return false
        }
        return deletionDoneCodes.contains(code) || (afterEarlierSend && code == "invalid_token")
    }

    /// The access token for a deletion. A retry after a deletion was sent must not mint the identity it is about to delete, so it signals ``MidgarIdentityGone`` where the session flow would mint.
    private func deletionToken(resuming: Bool) async throws -> String {
        guard resuming else {
            return try await accessToken()
        }
        return try await currentSession(allowMint: false).accessToken
    }

    /// The proof for `DELETE /me`: a key-bound session signs a fresh challenge, which also goes in as `clientData`; a session without a key sends the credential and needs no challenge.
    private func deletionBody() async throws -> DeleteBody {
        if try store.readSession()?.keyId == nil {
            return DeleteBody(assertion: nil, clientData: nil, credential: try sharedCredential())
        }
        let challenge: ChallengeReply = try await post("challenge", nil)
        let proof = try await proof(challenge: challenge.challenge)
        return DeleteBody(assertion: proof.assertion, clientData: proof.clientData, credential: proof.credential)
    }

    /// The proof for a change to the account. A session with a key signs SHA-256 of the challenge; a key that no longer exists ends the session, so the next call attaches again with a new key. There is no unattested fallback here: the service accepts only an assertion from a key-bound session and refuses the ID credential, so any other assertion failure is thrown and the session keeps its key. A keyless session, such as one that fell back after App Attest failed, proves itself with the credential.
    private func proof(challenge: String) async throws -> AccountProof {
        guard let keyID = try store.readSession()?.keyId else {
            return AccountProof(assertion: nil, clientData: nil, credential: try sharedCredential())
        }
        do {
            let assertion = try await attestation.generateAssertion(keyID, clientDataHash: MidgarDigest.sha256(utf8: challenge))
            return AccountProof(assertion: assertion.base64EncodedString(), clientData: challenge, credential: nil)
        } catch MidgarAttestationError.invalidKey {
            try discardSessionWithLostKey()
            throw MidgarAttestationError.invalidKey
        } catch MidgarAttestationError.unsupported {
            try discardSessionWithLostKey()
            throw MidgarAttestationError.unsupported
        }
    }

    private func discardSessionWithLostKey() throws {
        log.info("identity: the session key is gone, the next call attaches again with a new key")
        dropCachedSession()
        try store.deleteSession()
    }

    private func sharedCredential() throws -> String {
        guard let shared = try store.readShared() else {
            throw MidgarIdentityError.credentialUnavailable
        }
        return shared.credential
    }

    /// Records in the per-app item that a deletion is about to be sent.
    private func markDeletionSent() throws {
        guard var session = try store.readSession() else {
            return
        }
        session.deleteSentAt = clock()
        try store.writeSession(session)
    }

    private func clearDeletionMark() throws {
        guard var session = try store.readSession(), session.deleteSentAt != nil else {
            return
        }
        session.deleteSentAt = nil
        try store.writeSession(session)
    }

    /// Drops the cached token when the service called it stale, so the caller's next attempt starts from a fresh one.
    private func forgetTokenIfStale(_ error: MidgarHTTPError) {
        if let code = error.serverCode, staleTokenCodes.contains(code) {
            dropCachedSession()
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

extension MidgarHTTPError {
    /// True when the service answered with a 4xx status, so the request was refused before it changed anything. A lost connection, a timeout or a 5xx leaves that open.
    var wasRejectedByService: Bool {
        guard let status = httpStatus else {
            return false
        }
        return (400..<500).contains(status)
    }
}
