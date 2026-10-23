import Foundation

/// What a refresh attempt decided.
private enum RefreshOutcome {
    case refreshed(LiveSession)
    case attachAgain(reason: String)
}

/// The proof an attested key gives to mint or attach.
struct AttestationEvidence: Sendable {
    let keyID: String
    let attestation: String
    let challenge: String
}

private let attachAgainCodes: Set<String> = [
    "invalid_refresh_token",
    "refresh_token_reused",
    "assertion_required",
    "assertion_invalid",
    "identity_merged"
]

private let retryableEvidenceCodes: Set<String> = ["key_already_attested", "invalid_challenge"]

/// What identity answers (401) for an attestation it cannot accept. Every verification failure maps to this one code: an attestation made for another App ID (`rp_id_mismatch`), an environment this service does not take (`bad_aaguid`), a broken certificate chain, a wrong nonce.
private let attestationRejectionCodes: Set<String> = ["attestation_invalid"]

private let identityGoneCodes: Set<String> = ["identity_not_found", "credential_expired"]

/// Raised inside the session flow when the identity no longer exists and the caller asked for no new one to be minted.
struct MidgarIdentityGone: Error {}

extension MidgarIdentity {
    static let pendingSyncRetryInterval: TimeInterval = 3600
    static let pendingSyncPatience: TimeInterval = 7 * 24 * 3600

    /// Steps 1 to 3 of the session flow: refresh the stored session, else attach to the shared identity, else mint. With `allowMint` false the flow throws ``MidgarIdentityGone`` where it would mint.
    func establishSession(allowMint: Bool) async throws -> LiveSession {
        switch try store.readPerApp() {
        case .session(let stored):
            switch try await refresh(stored) {
            case .refreshed(let session):
                return session
            case .attachAgain(let reason):
                log.info("identity: stored session unusable (\(reason)), attaching again")
                dropCachedSession()
                try store.deleteSession()
            }
            return try await joinOrMint(pending: nil, allowMint: allowMint)
        case .pendingSync(let pending):
            return try await joinOrMint(pending: pending, allowMint: allowMint)
        case nil:
            return try await joinOrMint(pending: nil, allowMint: allowMint)
        }
    }

    private func joinOrMint(pending: PendingSync?, allowMint: Bool) async throws -> LiveSession {
        if let shared = try store.readShared() {
            return try await attach(shared, pending: pending, allowMint: allowMint)
        }
        guard allowMint else {
            throw MidgarIdentityGone()
        }
        return try await mint(replacingShared: false)
    }

    /// Step 1: exchanges the stored refresh token, signed with an assertion when the session has a key. Only the documented failures send the caller to attach again; everything else leaves the stored session as it is and throws.
    private func refresh(_ stored: StoredSession) async throws -> RefreshOutcome {
        var assertion: String?
        if let keyID = stored.keyId {
            guard attestation.isSupported else {
                return .attachAgain(reason: "App Attest unavailable for the session key")
            }
            do {
                let data = try await attestation.generateAssertion(
                    keyID,
                    clientDataHash: MidgarDigest.sha256(utf8: stored.refreshToken)
                )
                assertion = data.base64EncodedString()
            } catch MidgarAttestationError.invalidKey {
                return .attachAgain(reason: "session key is gone")
            } catch MidgarAttestationError.unsupported {
                return .attachAgain(reason: "App Attest unavailable for the session key")
            }
        }
        do {
            let reply: SessionReply = try await post(
                "refresh",
                RefreshBody(
                    refreshToken: stored.refreshToken,
                    assertion: assertion,
                    clientData: assertion == nil ? nil : stored.refreshToken
                )
            )
            try store.writeSession(StoredSession(refreshToken: reply.refreshToken, keyId: stored.keyId, midgarId: reply.midgarId))
            log.info("identity: session refreshed")
            return .refreshed(LiveSession(reply: reply, now: clock()))
        } catch let error as MidgarHTTPError {
            if let code = error.serverCode, attachAgainCodes.contains(code) {
                return .attachAgain(reason: code)
            }
            throw error
        }
    }

    /// Step 2: joins the shared identity with a session of this app. Step 4: what the service answers to a rejected attach decides whether the shared item survives (see ``rejectedAttach(_:shared:pending:allowMint:)``).
    private func attach(_ shared: SharedIdentity, pending: PendingSync?, allowMint: Bool) async throws -> LiveSession {
        let credentialDigest = MidgarDigest.sha256Hex(utf8: shared.credential)
        let pending = pending.flatMap { $0.credentialDigest == credentialDigest ? $0 : nil }
        if let pending, isWaitingForSync(pending) {
            throw MidgarIdentityError.credentialPendingSync
        }
        do {
            let (reply, keyID) = try await withEvidence { evidence in
                let session: SessionReply = try await self.post(
                    "attach",
                    AttachBody(
                        midgarId: shared.midgarId,
                        credential: shared.credential,
                        bundleId: self.bundleID,
                        keyId: evidence?.keyID,
                        attestation: evidence?.attestation,
                        challenge: evidence?.challenge
                    )
                )
                return (session, evidence?.keyID)
            }
            try store.writeSession(StoredSession(refreshToken: reply.refreshToken, keyId: keyID, midgarId: reply.midgarId))
            log.info("identity: attached to the shared identity (\(keyID == nil ? "unattested" : "attested"))")
            if reply.midgarId != shared.midgarId {
                log.info("identity: the shared identity was merged, adopted the surviving ID for this session")
            }
            return LiveSession(reply: reply, now: clock())
        } catch let error as MidgarHTTPError {
            return try await rejectedAttach(error, shared: shared, pending: pending, allowMint: allowMint)
        }
    }

    /// True while the last attempt with this credential is less than an hour old. A clock that moved backwards ends the wait.
    private func isWaitingForSync(_ pending: PendingSync) -> Bool {
        let elapsed = clock().timeIntervalSince(pending.lastAttempt)
        return elapsed >= 0 && elapsed < Self.pendingSyncRetryInterval
    }

    /// Acts on a failed attach. `identity_not_found` and `credential_expired` say the shared item is dead, so a new identity replaces it. `invalid_credential` says the identity exists and the credential is stale, because another device merged and rotated it and keychain sync is behind: the shared item stays, the attempt is recorded in the per-app item and a ``MidgarIdentityError/credentialPendingSync`` is thrown, and only seven days of continuous rejection of the same credential end in a new identity that Sign in with Apple can merge later. Everything else is rethrown.
    private func rejectedAttach(
        _ error: MidgarHTTPError,
        shared: SharedIdentity,
        pending: PendingSync?,
        allowMint: Bool
    ) async throws -> LiveSession {
        guard let code = error.serverCode else {
            throw error
        }
        if identityGoneCodes.contains(code) {
            guard allowMint else {
                throw MidgarIdentityGone()
            }
            log.warning("identity: the shared identity is gone (\(code)), minting a new identity that Sign in with Apple can merge later")
            return try await mint(replacingShared: true)
        }
        guard code == "invalid_credential" else {
            throw error
        }
        let now = clock()
        let firstFailure = pending?.firstFailure ?? now
        if allowMint, now.timeIntervalSince(firstFailure) >= Self.pendingSyncPatience {
            log.warning("identity: the shared credential has been rejected for seven days, minting a new identity that Sign in with Apple can merge later")
            return try await mint(replacingShared: true)
        }
        try store.writePendingSync(PendingSync(
            firstFailure: firstFailure,
            lastAttempt: now,
            credentialDigest: MidgarDigest.sha256Hex(utf8: shared.credential)
        ))
        log.info("identity: the shared credential was rejected, waiting for keychain sync before trying again")
        throw MidgarIdentityError.credentialPendingSync
    }

    /// Step 3: mints a new identity and stores it in both items, the shared one first so no other app can mint a second ID. When another app wrote the shared item while the mint was in flight, that identity wins and this app attaches to it.
    private func mint(replacingShared: Bool) async throws -> LiveSession {
        let (reply, keyID) = try await withEvidence { evidence -> (MintReply, String?) in
            if let evidence {
                let minted: MintReply = try await self.post(
                    "mint",
                    MintAttestedBody(
                        keyId: evidence.keyID,
                        attestation: evidence.attestation,
                        challenge: evidence.challenge,
                        bundleId: self.bundleID
                    )
                )
                return (minted, evidence.keyID)
            }
            let minted: MintReply = try await self.post("mint/unverified", MintUnverifiedBody(bundleId: self.bundleID))
            return (minted, nil)
        }
        let shared = SharedIdentity(midgarId: reply.session.midgarId, credential: reply.credential)
        if replacingShared {
            try store.writeShared(shared)
        } else if try !store.writeSharedIfAbsent(shared) {
            log.info("identity: another Midgar app created the shared identity first, attaching to it")
            return try await attach(try sharedWrittenByAnotherApp(), pending: nil, allowMint: true)
        }
        try store.writeSession(StoredSession(refreshToken: reply.session.refreshToken, keyId: keyID, midgarId: reply.session.midgarId))
        log.info("identity: minted a new identity (\(keyID == nil ? "unverified" : "attested"))")
        return LiveSession(reply: reply.session, now: clock())
    }

    /// The shared item another app wrote while this app was minting. The keychain refused the write because the slot is taken, so an empty read means the item exists but cannot be read here; that is reported instead of minting again, which would loop.
    private func sharedWrittenByAnotherApp() throws -> SharedIdentity {
        guard let shared = try store.readShared() else {
            throw MidgarIdentityError.corruptSharedItem
        }
        return shared
    }

    /// Runs a mint or attach with fresh attestation evidence where App Attest is supported. A used key or a spent challenge gets one more try with new ones, because the service consumes both. An attestation the service cannot accept (see ``attestationRejectionCodes``) is no reason to leave the app without a Midgar ID: the operation runs once more without evidence, which selects the unattested flows, and App Attest stays off for the rest of the process. Every other failure is thrown.
    private func withEvidence<Value: Sendable>(
        _ operation: (AttestationEvidence?) async throws -> Value
    ) async throws -> Value {
        var retried = false
        while true {
            let evidence = try await makeEvidence()
            do {
                return try await operation(evidence)
            } catch let error as MidgarHTTPError {
                guard evidence != nil, let code = error.serverCode else {
                    throw error
                }
                if attestationRejectionCodes.contains(code) {
                    attestationFailedThisProcess = true
                    log.warning("identity: the service rejected the attestation (\(code)), continuing unattested until the app restarts")
                    return try await operation(nil)
                }
                guard !retried, retryableEvidenceCodes.contains(code) else {
                    throw error
                }
                retried = true
                log.info("identity: attestation evidence rejected (\(code)), retrying with a new key")
            }
        }
    }

    /// A challenge, a new key and its attestation. Nil where App Attest is not supported or has failed earlier in this process, which selects the unattested flows. A client failure of App Attest itself (a missing entitlement, a different App ID, a key that cannot be made or attested) also yields nil and switches App Attest off for the rest of the process, so refreshes and attaches do not generate a key each time; the next launch tries again. Apple's service being unreachable and a cancelled task are thrown, because a later attempt can succeed and a keyless session stays keyless.
    private func makeEvidence() async throws -> AttestationEvidence? {
        guard attestation.isSupported else {
            return nil
        }
        guard !attestationFailedThisProcess else {
            log.info("identity: App Attest failed earlier in this process, continuing unattested")
            return nil
        }
        let reply: ChallengeReply = try await post("challenge", nil)
        do {
            let keyID = try await attestation.generateKey()
            let object = try await attestation.attestKey(keyID, clientDataHash: MidgarDigest.sha256(utf8: reply.challenge))
            return AttestationEvidence(keyID: keyID, attestation: object.base64EncodedString(), challenge: reply.challenge)
        } catch is CancellationError {
            throw CancellationError()
        } catch MidgarAttestationError.unavailable {
            throw MidgarAttestationError.unavailable
        } catch {
            attestationFailedThisProcess = true
            log.warning("identity: App Attest failed (\(Self.attestationErrorKind(error))), continuing unattested until the app restarts")
            return nil
        }
    }

    /// The case name of a ``MidgarAttestationError`` or the type of any other error, never its message.
    private static func attestationErrorKind(_ error: any Error) -> String {
        if let failure = error as? MidgarAttestationError {
            return "\(failure)"
        }
        return String(describing: type(of: error))
    }

    /// POSTs to the identity service. 401s keep their error code so the flows can act on it.
    func post<Reply: Decodable & Sendable>(
        _ path: String,
        _ body: (any Encodable & Sendable)?,
        bearer: String? = nil
    ) async throws -> Reply {
        try await http.send(request(path, method: .post, body: body, bearer: bearer))
    }

    func request(
        _ path: String,
        method: MidgarHTTPMethod,
        body: (any Encodable & Sendable)? = nil,
        bearer: String? = nil,
        neverRetries: Bool = false
    ) -> MidgarRequest {
        MidgarRequest(
            service: Self.service,
            path: path,
            method: method,
            headers: bearer.map { ["Authorization": "Bearer \($0)"] } ?? [:],
            body: body,
            preservesUnauthorizedCode: true,
            neverRetries: neverRetries
        )
    }
}
