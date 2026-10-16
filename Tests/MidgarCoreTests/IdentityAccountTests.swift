import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-4")
private let keyedSession = StoredSession(refreshToken: "refresh-old", keyId: "key-device", midgarId: "id-shared")
private let unkeyedSession = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared")
private let challengeReply = StubReply.json(200, #"{"challenge":"chal-1","expiresIn":300}"#)

private func refreshReply(token: String = freshToken(), refresh: String = "refresh-new") -> StubReply {
    .json(200, sessionJSON(midgarId: "id-shared", accessToken: token, refreshToken: refresh))
}

@Suite struct IdentityAccountTests {
    @Test func preparingALinkAsksForAChallengeAndDerivesTheNonce() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(challengeReply)

        let request = try await harness.identity.prepareAppleLink()

        #expect(request.nonce == "dc8f6ca3db77aa23ae2a3c078b4c9952be4223b4bbabeb4eaae95c235baa2cb9")
        #expect(harness.paths == ["POST /v1/identity/challenge"])
        #expect(harness.host.requests[0].headers["X-App-ID"] == IdentityHarness.appID)
    }

    @Test func aKeyBoundSessionProvesTheLinkWithAnAssertionOverTheChallenge() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(challengeReply, refreshReply(), .json(200, #"{"midgarId":"id-shared","merged":false}"#))

        let request = try await harness.identity.prepareAppleLink()
        let result = try await harness.identity.linkApple(identityToken: "apple-token", with: request)

        #expect(result == MidgarAppleLinkResult(midgarId: "id-shared", merged: false))
        let link = harness.host.requests[2]
        #expect(link.url.path == "/v1/identity/link/apple")
        #expect(link.headers["Authorization"] == "Bearer \(freshToken())")
        let body = bodyObject(link)
        #expect(Set(body.keys) == ["identityToken", "challenge", "assertion"])
        #expect(body["identityToken"] as? String == "apple-token")
        #expect(body["challenge"] as? String == "chal-1")
        #expect(body["assertion"] as? String == Data("assertion-2-by-key-device".utf8).base64EncodedString())
        let signed = try #require(harness.attestation.assertions.last)
        #expect(signed.keyID == "key-device")
        #expect(signed.hash == MidgarDigest.sha256(Data("chal-1".utf8)))
        #expect(try harness.storedShared() == shared)
        #expect(try harness.storedSession()?.refreshToken == "refresh-new")
    }

    @Test func aSessionWithoutAKeyProvesTheLinkWithTheCredential() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyedSession)
        harness.enqueue(challengeReply, refreshReply(), .json(200, #"{"midgarId":"id-shared","merged":false}"#))

        let request = try await harness.identity.prepareAppleLink()
        _ = try await harness.identity.linkApple(identityToken: "apple-token", with: request)

        let body = bodyObject(harness.host.requests[2])
        #expect(Set(body.keys) == ["identityToken", "challenge", "credential"])
        #expect(body["credential"] as? String == "CRED-SECRET-4")
        #expect(body["challenge"] as? String == "chal-1")
        #expect(harness.attestation.assertions.isEmpty)
    }

    @Test func aMergeRewritesTheSharedItemAndAdoptsTheNewSession() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        let survivorToken = freshToken("app_attest", lifetime: 1800)
        harness.enqueue(
            challengeReply,
            refreshReply(),
            .json(200, sessionJSON(
                midgarId: "id-survivor", accessToken: survivorToken, refreshToken: "refresh-survivor",
                extra: ["merged": true, "credential": "CRED-ROTATED"]
            ))
        )

        let request = try await harness.identity.prepareAppleLink()
        let result = try await harness.identity.linkApple(identityToken: "apple-token", with: request)

        #expect(result == MidgarAppleLinkResult(midgarId: "id-survivor", merged: true))
        #expect(try harness.storedShared() == SharedIdentity(midgarId: "id-survivor", credential: "CRED-ROTATED"))
        #expect(try harness.storedSession() == StoredSession(
            refreshToken: "refresh-survivor", keyId: "key-device", midgarId: "id-survivor"
        ))
        #expect(try await harness.identity.accessToken() == survivorToken)
        #expect(try await harness.identity.midgarId == "id-survivor")
        #expect(try await harness.identity.tier == .appAttest)
        #expect(harness.host.requests.count == 3)
        #expect(!harness.logs.all.contains { $0.contains("CRED-ROTATED") || $0.contains("refresh-survivor") })
    }

    @Test func aMergeReplyMissingTheNewCredentialIsRejectedWithoutStoringAnything() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(
            challengeReply,
            refreshReply(),
            .json(200, sessionJSON(midgarId: "id-survivor", accessToken: freshToken(), refreshToken: "r", extra: ["merged": true]))
        )

        let request = try await harness.identity.prepareAppleLink()
        let error = await thrownIdentityError {
            try await harness.identity.linkApple(identityToken: "apple-token", with: request)
        }

        #expect(error == .malformedResponse)
        #expect(try harness.storedShared() == shared)
    }

    @Test func aStaleTokenOnLinkIsNotRepeatedBecauseTheChallengeIsSpent() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(
            challengeReply,
            refreshReply(),
            .json(401, errorJSON("token_expired")),
            refreshReply(refresh: "refresh-3")
        )

        let request = try await harness.identity.prepareAppleLink()
        let error = await thrownIdentityError {
            try await harness.identity.linkApple(identityToken: "apple-token", with: request)
        }
        _ = try await harness.identity.accessToken()

        #expect(error == .http(.server(status: 401, code: "token_expired", message: "m")))
        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/refresh", "POST /v1/identity/link/apple",
            "POST /v1/identity/refresh"
        ])
    }

    @Test func aLostSessionKeyEndsTheSessionSoTheNextCallAttachesAgain() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(challengeReply, refreshReply())
        let request = try await harness.identity.prepareAppleLink()
        _ = try await harness.identity.accessToken()
        harness.attestation.failAssertion(with: .invalidKey)

        let error = await thrownIdentityError {
            try await harness.identity.linkApple(identityToken: "apple-token", with: request)
        }

        #expect(error == .attestation(.invalidKey))
        #expect(try harness.storedSession() == nil)
        #expect(harness.paths.count == 2)
    }

    @Test func anIdentityWithoutASharedItemCannotProveALinkWithACredential() async throws {
        let harness = try IdentityHarness(attested: false, session: unkeyedSession)
        harness.enqueue(challengeReply, refreshReply())

        let request = try await harness.identity.prepareAppleLink()
        let error = await thrownIdentityError {
            try await harness.identity.linkApple(identityToken: "apple-token", with: request)
        }

        #expect(error == .credentialUnavailable)
    }

    @Test func exportReturnsTheRawJSON() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        let raw = #"{"midgarId":"id-shared",  "keys":[]}"#
        harness.enqueue(refreshReply(), .json(200, raw))

        let data = try await harness.identity.export()

        #expect(data == Data(raw.utf8))
        let request = harness.host.requests[1]
        #expect(request.method == "GET")
        #expect(request.url.path == "/v1/identity/me/export")
        #expect(request.headers["Authorization"] == "Bearer \(freshToken())")
    }

    @Test func theCredentialLeavesTheDeviceOnlyInTheAttachBody() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            .json(200, #"{"challenge":"chal-1","expiresIn":300}"#),
            .json(200, sessionJSON(midgarId: "id-shared", accessToken: freshToken("app_attest"), refreshToken: "refresh-a")),
            .json(200, "{}"),
            .json(200, sessionJSON(midgarId: "id-shared", accessToken: freshToken("app_attest"), refreshToken: "refresh-b"))
        )

        _ = try await harness.identity.accessToken()
        _ = try await harness.identity.export()
        harness.clock.advance(4000)
        _ = try await harness.identity.accessToken()

        for request in harness.host.requests {
            let isAttach = request.url.path == "/v1/identity/attach"
            let text = "\(request.url.absoluteString) \(request.headers) \(bodyText(request))"
            #expect(text.contains(shared.credential) == isAttach)
        }
        let secrets = [shared.credential, "refresh-a", "refresh-b", freshToken("app_attest"), "key-1", "id-shared"]
        for secret in secrets {
            #expect(!harness.logs.all.contains { $0.contains(secret) })
        }
    }
}
