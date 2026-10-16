import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-5")
private let keyedSession = StoredSession(refreshToken: "refresh-old", keyId: "key-device", midgarId: "id-shared")
private let unkeyedSession = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared")
private let challengeReply = StubReply.json(200, #"{"challenge":"chal-1","expiresIn":300}"#)

private func refreshReply(token: String = freshToken(), refresh: String = "refresh-new") -> StubReply {
    .json(200, sessionJSON(midgarId: "id-shared", accessToken: token, refreshToken: refresh))
}

private func deletions(_ harness: IdentityHarness) -> [CapturedRequest] {
    harness.host.requests.filter { $0.method == "DELETE" }
}

@Suite struct IdentityDeleteTests {
    @Test func aKeyBoundSessionDeletesWithAnAssertionOverAFreshChallenge() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(refreshReply(), challengeReply, .json(204, ""))

        try await harness.identity.deleteIdentity()

        #expect(harness.paths == ["POST /v1/identity/refresh", "POST /v1/identity/challenge", "DELETE /v1/identity/me"])
        let deletion = harness.host.requests[2]
        #expect(deletion.headers["Authorization"] == "Bearer \(freshToken())")
        let body = bodyObject(deletion)
        #expect(Set(body.keys) == ["assertion", "clientData"])
        #expect(body["clientData"] as? String == "chal-1")
        #expect(body["assertion"] as? String == Data("assertion-2-by-key-device".utf8).base64EncodedString())
        #expect(harness.attestation.assertions.last?.hash == MidgarDigest.sha256(Data("chal-1".utf8)))
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
        #expect(try harness.keychain.read(.session(appID: IdentityHarness.appID)) == nil)
    }

    @Test func aSessionWithoutAKeyDeletesWithTheCredentialAndNoChallenge() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
        harness.enqueue(refreshReply(), .json(204, ""))

        try await harness.identity.deleteIdentity()

        #expect(harness.paths == ["POST /v1/identity/refresh", "DELETE /v1/identity/me"])
        let body = bodyObject(harness.host.requests[1])
        #expect(Set(body.keys) == ["credential"])
        #expect(body["credential"] as? String == "CRED-SECRET-5")
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
    }

    @Test func theDeletionIsSentOnceEvenWhenTheAnswerIsLost() async throws {
        let failures: [StubReply] = [.failing(.timedOut), .failing(.networkConnectionLost), .json(503, errorJSON("down"))]
        for failure in failures {
            let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
            harness.enqueue(refreshReply(), failure, .json(204, ""))

            let error = await thrownIdentityError { try await harness.identity.deleteIdentity() }

            #expect(error?.isTransient == true)
            #expect(deletions(harness).count == 1)
            #expect(try harness.storedShared() == shared)
            #expect(try harness.storedSession()?.deleteSentAt == identityEpoch)
        }
    }

    @Test func aRetryThatFindsTheIdentityGoneCountsTheDeletionAsDone() async throws {
        for answer in [StubReply.json(401, errorJSON("invalid_token")), .json(404, errorJSON("identity_not_found"))] {
            let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
            harness.enqueue(refreshReply(), .failing(.timedOut), answer)
            _ = await thrownIdentityError { try await harness.identity.deleteIdentity() }

            try await harness.identity.deleteIdentity()

            #expect(deletions(harness).count == 2)
            #expect(try harness.storedShared() == nil)
            #expect(try harness.storedSession() == nil)
        }
    }

    @Test func aLaterCallAfterARestartFindsTheRefreshTokensGoneAndTheIdentityMissing() async throws {
        let sent = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared", deleteSentAt: identityEpoch)
        let harness = try IdentityHarness(attested: false, shared: shared, session: sent)
        harness.enqueue(
            .json(401, errorJSON("invalid_refresh_token")),
            .json(404, errorJSON("identity_not_found"))
        )

        try await harness.identity.deleteIdentity()

        #expect(harness.paths == ["POST /v1/identity/refresh", "POST /v1/identity/attach"])
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
        #expect(!harness.logs.warnings.contains { $0.contains("minting") })
    }

    @Test func aLaterCallThatStillFindsTheIdentityDeletesItAgain() async throws {
        let sent = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared", deleteSentAt: identityEpoch)
        let harness = try IdentityHarness(attested: false, shared: shared, session: sent)
        harness.enqueue(refreshReply(), .json(204, ""))

        try await harness.identity.deleteIdentity()

        #expect(harness.paths == ["POST /v1/identity/refresh", "DELETE /v1/identity/me"])
        #expect(try harness.storedShared() == nil)
    }

    @Test func aRejectedDeletionKeepsBothItemsAndClearsTheMark() async throws {
        for answer in [StubReply.json(403, errorJSON("forbidden")), .json(401, errorJSON("invalid_credential"))] {
            let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
            harness.enqueue(refreshReply(), answer)

            let error = await thrownIdentityError { try await harness.identity.deleteIdentity() }

            #expect(error != nil)
            #expect(try harness.storedShared() == shared)
            #expect(try harness.storedSession()?.deleteSentAt == nil)
            #expect(deletions(harness).count == 1)
        }
    }

    @Test func aStaleTokenRefreshesOnceAndSendsTheDeletionWithAFreshChallenge() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        let second = freshToken("development", lifetime: 7200)
        harness.enqueue(
            refreshReply(), challengeReply,
            .json(401, errorJSON("token_expired")),
            refreshReply(token: second, refresh: "refresh-3"),
            .json(200, #"{"challenge":"chal-2","expiresIn":300}"#),
            .json(204, "")
        )

        try await harness.identity.deleteIdentity()

        #expect(harness.paths == [
            "POST /v1/identity/refresh", "POST /v1/identity/challenge", "DELETE /v1/identity/me",
            "POST /v1/identity/refresh", "POST /v1/identity/challenge", "DELETE /v1/identity/me"
        ])
        #expect(harness.host.requests[5].headers["Authorization"] == "Bearer \(second)")
        #expect(bodyObject(harness.host.requests[5])["clientData"] as? String == "chal-2")
        #expect(try harness.storedShared() == nil)
    }

    @Test func aSecondStaleTokenErrorIsThrownAndNothingIsCleared() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
        harness.enqueue(
            refreshReply(), .json(401, errorJSON("invalid_token")),
            refreshReply(refresh: "refresh-3"), .json(401, errorJSON("invalid_token"))
        )

        let error = await thrownIdentityError { try await harness.identity.deleteIdentity() }

        #expect(error == .http(.server(status: 401, code: "invalid_token", message: "m")))
        #expect(deletions(harness).count == 2)
        #expect(try harness.storedShared() == shared)
    }

    @Test func deletingWhenNothingIsStoredMakesNoRequest() async throws {
        let harness = try IdentityHarness(attested: false)

        try await harness.identity.deleteIdentity()

        #expect(harness.host.requests.isEmpty)
    }

    @Test func afterDeletionTheNextCallMintsANewIdentity() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
        harness.enqueue(
            refreshReply(), .json(204, ""),
            .json(201, sessionJSON(
                midgarId: "id-new", accessToken: freshToken(), refreshToken: "r", extra: ["credential": "CRED-NEW"]
            ))
        )

        try await harness.identity.deleteIdentity()
        _ = try await harness.identity.accessToken()

        #expect(harness.paths.last == "POST /v1/identity/mint/unverified")
        #expect(try harness.storedShared()?.midgarId == "id-new")
    }

    @Test func theCredentialAndAssertionNeverReachTheLogs() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
        harness.enqueue(refreshReply(), .json(204, ""))

        try await harness.identity.deleteIdentity()

        for secret in ["CRED-SECRET-5", "refresh-new", "id-shared"] {
            #expect(!harness.logs.all.contains { $0.contains(secret) })
        }
    }
}
