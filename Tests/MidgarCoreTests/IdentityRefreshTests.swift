import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-3")
private let session = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared")
private let keyedSession = StoredSession(refreshToken: "refresh-old", keyId: "key-device", midgarId: "id-shared")

private func refreshReply(_ id: String = "id-shared", refresh: String = "refresh-new", token: String = freshToken()) -> StubReply {
    .json(200, sessionJSON(midgarId: id, accessToken: token, refreshToken: refresh))
}

private func attachReply(refresh: String = "refresh-attached") -> StubReply {
    .json(200, sessionJSON(midgarId: "id-shared", accessToken: freshToken(), refreshToken: refresh))
}

@Suite struct IdentityRefreshTests {
    @Test func refreshesAStoredSessionWithoutAKeyUsingTheTokenAlone() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: session)
        harness.enqueue(refreshReply())

        let token = try await harness.identity.accessToken()

        #expect(token == freshToken())
        #expect(harness.paths == ["POST /v1/identity/refresh"])
        let body = bodyObject(harness.host.requests[0])
        #expect(body["refreshToken"] as? String == "refresh-old")
        #expect(body["assertion"] == nil)
        #expect(body["clientData"] == nil)
        #expect(harness.attestation.assertions.isEmpty)
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-new", keyId: nil, midgarId: "id-shared"))
    }

    @Test func aSessionWithAKeySignsTheRefreshTokenWithAnAssertion() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(refreshReply())

        _ = try await harness.identity.accessToken()

        let body = bodyObject(harness.host.requests[0])
        #expect(body["clientData"] as? String == "refresh-old")
        #expect(body["assertion"] as? String == Data("assertion-1-by-key-device".utf8).base64EncodedString())
        let asserted = try #require(harness.attestation.assertions.first)
        #expect(asserted.keyID == "key-device")
        #expect(asserted.hash == MidgarDigest.sha256(Data("refresh-old".utf8)))
        #expect(try harness.storedSession()?.keyId == "key-device")
    }

    @Test(arguments: ["invalid_refresh_token", "refresh_token_reused", "assertion_required", "assertion_invalid", "identity_merged"])
    func aRejectedRefreshDeletesTheSessionAndAttachesAgain(code: String) async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        harness.enqueue(.json(401, errorJSON(code)), attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/refresh", "POST /v1/identity/attach"])
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-attached", keyId: nil, midgarId: "id-shared"))
        #expect(try harness.storedShared() == shared)
    }

    @Test func aRejectedRefreshWithoutASharedItemMintsANewIdentity() async throws {
        let harness = try IdentityHarness(attested: false, session: session)
        harness.enqueue(
            .json(401, errorJSON("invalid_refresh_token")),
            .json(201, sessionJSON(
                midgarId: "id-new", accessToken: freshToken(), refreshToken: "refresh-m", extra: ["credential": "CRED-NEW"]
            ))
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/refresh", "POST /v1/identity/mint/unverified"])
        #expect(try harness.storedShared() == SharedIdentity(midgarId: "id-new", credential: "CRED-NEW"))
    }

    @Test func aMissingKeySkipsTheRefreshAndAttachesWithANewKey() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.attestation.failAssertion(with: .invalidKey)
        harness.enqueue(.json(200, #"{"challenge":"chal-1","expiresIn":300}"#), attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/attach"])
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-attached", keyId: "key-1", midgarId: "id-shared"))
    }

    @Test func aKeyedSessionOnADeviceWithoutAppAttestAttachesUnattested() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: keyedSession)
        harness.enqueue(attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/attach"])
        #expect(try harness.storedSession()?.keyId == nil)
    }

    @Test func aTransientAssertionFailureKeepsEverythingStoredAndThrows() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.attestation.failAssertion(with: .unavailable)

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .attestation(.unavailable))
        #expect(harness.host.requests.isEmpty)
        #expect(try harness.storedSession() == keyedSession)
    }

    @Test func transientRefreshFailuresKeepEverythingStoredAndThrow() async throws {
        let failures: [StubReply] = [
            .failing(.notConnectedToInternet), .failing(.timedOut), .json(500, errorJSON("boom")),
            .json(503, errorJSON("down")), .json(429, errorJSON("rate_limited"))
        ]
        for failure in failures {
            let harness = try IdentityHarness(attested: false, shared: shared, session: session)
            harness.enqueue(failure)

            let error = await thrownIdentityError { try await harness.identity.accessToken() }

            #expect(error?.isTransient == true)
            #expect(harness.paths == ["POST /v1/identity/refresh"])
            #expect(try harness.storedSession() == session)
            #expect(try harness.storedShared() == shared)
        }
    }

    @Test func anUnlistedRefreshErrorThrowsWithoutTouchingTheSession() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        harness.enqueue(.json(400, errorJSON("invalid_request")))

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .http(.server(status: 400, code: "invalid_request", message: "m")))
        #expect(try harness.storedSession() == session)
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        harness.enqueue(refreshReply().delayed(by: 0.3))

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await harness.identity.accessToken() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(Set(tokens) == [freshToken()])
        #expect(harness.paths == ["POST /v1/identity/refresh"])
    }

    @Test func aFailedFlightIsNotCachedAndTheNextCallTriesAgain() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        harness.enqueue(.failing(.notConnectedToInternet), refreshReply())

        let first = await thrownIdentityError { try await harness.identity.accessToken() }
        let second = try await harness.identity.accessToken()

        #expect(first?.isTransient == true)
        #expect(second == freshToken())
        #expect(harness.paths == ["POST /v1/identity/refresh", "POST /v1/identity/refresh"])
    }

    @Test func refreshesOnlyWhenTheTokenExpiresWithinSixtySeconds() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        let first = freshToken(lifetime: 3600)
        let second = freshToken("development", lifetime: 7200)
        harness.enqueue(refreshReply(token: first), refreshReply(refresh: "refresh-3", token: second))

        #expect(try await harness.identity.accessToken() == first)
        harness.clock.advance(3600 - 61)
        #expect(try await harness.identity.accessToken() == first)
        #expect(harness.host.requests.count == 1)

        harness.clock.advance(2)
        #expect(try await harness.identity.accessToken() == second)
        #expect(harness.host.requests.count == 2)
        #expect(bodyObject(harness.host.requests[1])["refreshToken"] as? String == "refresh-new")
        #expect(try await harness.identity.tier == .development)
    }

    @Test func aTokenWithoutReadableClaimsFallsBackToExpiresInAndTheUnverifiedTier() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: session)
        harness.enqueue(refreshReply(token: "opaque-token"))

        #expect(try await harness.identity.accessToken() == "opaque-token")
        #expect(try await harness.identity.tier == .unverified)
        harness.clock.advance(3600 - 30)
        harness.enqueue(refreshReply(refresh: "refresh-3", token: freshToken()))
        _ = try await harness.identity.accessToken()
        #expect(harness.host.requests.count == 2)
    }
}
