import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-4")
private let keyedSession = StoredSession(refreshToken: "refresh-old", keyId: "key-device", midgarId: "id-shared")

private func refreshReply(token: String = freshToken(), refresh: String = "refresh-new") -> StubReply {
    .json(200, sessionJSON(midgarId: "id-shared", accessToken: token, refreshToken: refresh))
}

@Suite struct IdentityAccountTests {
    @Test func linkingWithoutAMergeChangesNothingStored() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(refreshReply(), .json(200, #"{"midgarId":"id-shared","merged":false}"#))

        let result = try await harness.identity.linkApple(identityToken: "apple-token")

        #expect(result == MidgarAppleLinkResult(midgarId: "id-shared", merged: false))
        let link = harness.host.requests[1]
        #expect(link.url.path == "/v1/identity/link/apple")
        #expect(link.headers["Authorization"] == "Bearer \(freshToken())")
        #expect(bodyObject(link) as? [String: String] == ["identityToken": "apple-token"])
        #expect(try harness.storedShared() == shared)
        #expect(try harness.storedSession()?.refreshToken == "refresh-new")
    }

    @Test func aMergeRewritesTheSharedItemAndAdoptsTheNewSession() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        let survivorToken = freshToken("app_attest", lifetime: 1800)
        harness.enqueue(
            refreshReply(),
            .json(200, sessionJSON(
                midgarId: "id-survivor", accessToken: survivorToken, refreshToken: "refresh-survivor",
                extra: ["merged": true, "credential": "CRED-ROTATED"]
            ))
        )

        let result = try await harness.identity.linkApple(identityToken: "apple-token")

        #expect(result == MidgarAppleLinkResult(midgarId: "id-survivor", merged: true))
        #expect(try harness.storedShared() == SharedIdentity(midgarId: "id-survivor", credential: "CRED-ROTATED"))
        #expect(try harness.storedSession() == StoredSession(
            refreshToken: "refresh-survivor", keyId: "key-device", midgarId: "id-survivor"
        ))
        #expect(try await harness.identity.accessToken() == survivorToken)
        #expect(try await harness.identity.midgarId == "id-survivor")
        #expect(try await harness.identity.tier == .appAttest)
        #expect(harness.host.requests.count == 2)
        #expect(!harness.logs.all.contains { $0.contains("CRED-ROTATED") || $0.contains("refresh-survivor") })
    }

    @Test func aMergeReplyMissingTheNewCredentialIsRejectedWithoutStoringAnything() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(
            refreshReply(),
            .json(200, sessionJSON(midgarId: "id-survivor", accessToken: freshToken(), refreshToken: "r", extra: ["merged": true]))
        )

        let error = await thrownIdentityError { try await harness.identity.linkApple(identityToken: "apple-token") }

        #expect(error == .malformedResponse)
        #expect(try harness.storedShared() == shared)
    }

    @Test func aStaleTokenRefreshesOnceAndRepeatsTheBearerCall() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        let second = freshToken("development", lifetime: 7200)
        harness.enqueue(
            refreshReply(),
            .json(401, errorJSON("token_expired")),
            refreshReply(token: second, refresh: "refresh-3"),
            .json(200, #"{"midgarId":"id-shared","merged":false}"#)
        )

        _ = try await harness.identity.linkApple(identityToken: "apple-token")

        #expect(harness.paths == [
            "POST /v1/identity/refresh", "POST /v1/identity/link/apple",
            "POST /v1/identity/refresh", "POST /v1/identity/link/apple"
        ])
        #expect(harness.host.requests[3].headers["Authorization"] == "Bearer \(second)")
    }

    @Test func aSecondStaleTokenErrorIsThrown() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(
            refreshReply(), .json(401, errorJSON("invalid_token")),
            refreshReply(refresh: "refresh-3"), .json(401, errorJSON("invalid_token"))
        )

        let error = await thrownIdentityError { try await harness.identity.linkApple(identityToken: "apple-token") }

        #expect(error == .http(.server(status: 401, code: "invalid_token", message: "m")))
        #expect(harness.host.requests.count == 4)
    }

    @Test func deletingTheIdentityRemovesBothKeychainItems() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(refreshReply(), .json(204, ""))

        try await harness.identity.deleteIdentity()

        let deletion = harness.host.requests[1]
        #expect(deletion.method == "DELETE")
        #expect(deletion.url.path == "/v1/identity/me")
        #expect(deletion.headers["Authorization"] == "Bearer \(freshToken())")
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
        #expect(try harness.keychain.read(.session(appID: IdentityHarness.appID)) == nil)
    }

    @Test func aFailedDeletionKeepsBothKeychainItems() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared, session: keyedSession)
        harness.enqueue(refreshReply(), .json(403, errorJSON("forbidden")))

        let error = await thrownIdentityError { try await harness.identity.deleteIdentity() }

        #expect(error != nil)
        #expect(try harness.storedShared() == shared)
        #expect(try harness.storedSession() != nil)
    }

    @Test func deletingWhenNothingIsStoredMakesNoRequest() async throws {
        let harness = try IdentityHarness(attested: false)

        try await harness.identity.deleteIdentity()

        #expect(harness.host.requests.isEmpty)
    }

    @Test func afterDeletionTheNextCallMintsANewIdentity() async throws {
        let unkeyed = StoredSession(refreshToken: "refresh-old", keyId: nil, midgarId: "id-shared")
        let harness = try IdentityHarness(attested: false, shared: shared, session: unkeyed)
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
