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

extension MidgarIdentity {
    /// Steps 1 to 3 of the session flow: refresh the stored session, else attach to the shared identity, else mint.
    func establishSession() async throws -> LiveSession {
        if let stored = try store.readSession() {
            switch try await refresh(stored) {
            case .refreshed(let session):
                return session
            case .attachAgain(let reason):
                log.info("identity: stored session unusable (\(reason)), attaching again")
                try store.deleteSession()
            }
        }
        return try await joinOrMint()
    }

    private func joinOrMint() async throws -> LiveSession {
        if let shared = try store.readShared() {
            return try await attach(shared)
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

    /// Step 2: joins the shared identity with a session of this app. Step 4: a credential the service no longer accepts forks a new identity.
    private func attach(_ shared: SharedIdentity) async throws -> LiveSession {
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
        } catch let error as MidgarHTTPError where error.serverCode == "invalid_credential" {
            log.warning("identity: the shared credential was rejected, minting a new identity that Sign in with Apple can merge later")
            return try await mint(replacingShared: true)
        }
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
            return try await joinOrMint()
        }
        try store.writeSession(StoredSession(refreshToken: reply.session.refreshToken, keyId: keyID, midgarId: reply.session.midgarId))
        log.info("identity: minted a new identity (\(keyID == nil ? "unverified" : "attested"))")
        return LiveSession(reply: reply.session, now: clock())
    }

    /// Runs a mint or attach with fresh attestation evidence where App Attest is supported. A used key or a spent challenge gets one more try with new ones, because the service consumes both.
    private func withEvidence<Value: Sendable>(
        _ operation: (AttestationEvidence?) async throws -> Value
    ) async throws -> Value {
        var retried = false
        while true {
            let evidence = try await makeEvidence()
            do {
                return try await operation(evidence)
            } catch let error as MidgarHTTPError {
                guard evidence != nil, !retried, let code = error.serverCode, retryableEvidenceCodes.contains(code) else {
                    throw error
                }
                retried = true
                log.info("identity: attestation evidence rejected (\(code)), retrying with a new key")
            }
        }
    }

    /// A challenge, a new key and its attestation. Nil where App Attest is not supported, which selects the unattested flows.
    private func makeEvidence() async throws -> AttestationEvidence? {
        guard attestation.isSupported else {
            return nil
        }
        do {
            let reply: ChallengeReply = try await post("challenge", nil)
            let keyID = try await attestation.generateKey()
            let object = try await attestation.attestKey(keyID, clientDataHash: MidgarDigest.sha256(utf8: reply.challenge))
            return AttestationEvidence(keyID: keyID, attestation: object.base64EncodedString(), challenge: reply.challenge)
        } catch MidgarAttestationError.unsupported {
            log.info("identity: App Attest unsupported on this device, continuing unattested")
            return nil
        }
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
        bearer: String? = nil
    ) -> MidgarRequest {
        MidgarRequest(
            service: Self.service,
            path: path,
            method: method,
            headers: bearer.map { ["Authorization": "Bearer \($0)"] } ?? [:],
            body: body,
            preservesUnauthorizedCode: true
        )
    }
}
