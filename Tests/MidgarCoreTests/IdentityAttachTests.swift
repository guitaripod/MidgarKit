import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-2")

private func attachReply(_ id: String = "id-shared", refresh: String = "refresh-a", tier: String = "unverified") -> StubReply {
    .json(200, sessionJSON(midgarId: id, accessToken: freshToken(tier), refreshToken: refresh))
}

private let challengeReply = StubReply.json(200, #"{"challenge":"chal-1","expiresIn":300}"#)

@Suite struct IdentityAttachTests {
    @Test func attachesWithoutAttestationWhenAppAttestIsUnsupported() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared)
        harness.enqueue(attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/attach"])
        let body = bodyObject(harness.host.requests[0])
        #expect(body["midgarId"] as? String == "id-shared")
        #expect(body["credential"] as? String == "CRED-SECRET-2")
        #expect(body["bundleId"] as? String == IdentityHarness.bundleID)
        #expect(body["keyId"] == nil)
        #expect(body["attestation"] == nil)
        #expect(body["challenge"] == nil)
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-a", keyId: nil, midgarId: "id-shared"))
        #expect(try harness.storedShared() == shared)
    }

    @Test func attachesWithAFreshAttestedKeyWhenSupported() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(challengeReply, attachReply(tier: "app_attest"))

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/attach"])
        let body = bodyObject(harness.host.requests[1])
        #expect(body["keyId"] as? String == "key-1")
        #expect(body["challenge"] as? String == "chal-1")
        #expect(body["attestation"] as? String == Data("attestation-of-key-1".utf8).base64EncodedString())
        #expect(harness.attestation.attestations.first?.hash == MidgarDigest.sha256(Data("chal-1".utf8)))
        #expect(try harness.storedSession()?.keyId == "key-1")
    }

    @Test func attachingAfterAMergeStoresTheReturnedIDAndLeavesTheSharedItemAlone() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared)
        harness.enqueue(attachReply("id-survivor"))

        _ = try await harness.identity.accessToken()

        #expect(try harness.storedSession()?.midgarId == "id-survivor")
        #expect(try harness.storedShared() == shared)
        #expect(try await harness.identity.midgarId == "id-survivor")
    }

    @Test func aUsedKeyGetsOneRetryWithANewChallengeAndKey() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            challengeReply,
            .json(409, errorJSON("key_already_attested")),
            .json(200, #"{"challenge":"chal-2","expiresIn":300}"#),
            attachReply()
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/attach",
            "POST /v1/identity/challenge", "POST /v1/identity/attach"
        ])
        #expect(bodyObject(harness.host.requests[3])["keyId"] as? String == "key-2")
        #expect(try harness.storedSession()?.keyId == "key-2")
    }

    @Test func aSecondRejectionOfTheEvidenceIsThrown() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            challengeReply, .json(401, errorJSON("invalid_challenge")),
            challengeReply, .json(401, errorJSON("invalid_challenge"))
        )

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .http(.server(status: 401, code: "invalid_challenge", message: "m")))
        #expect(try harness.storedSession() == nil)
    }

    @Test func aRejectedCredentialForksANewIdentityAndOverwritesTheSharedItem() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared)
        harness.enqueue(
            .json(401, errorJSON("invalid_credential")),
            .json(201, sessionJSON(
                midgarId: "id-fork", accessToken: freshToken(), refreshToken: "refresh-f",
                extra: ["credential": "CRED-FORK"]
            ))
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/attach", "POST /v1/identity/mint/unverified"])
        #expect(try harness.storedShared() == SharedIdentity(midgarId: "id-fork", credential: "CRED-FORK"))
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-f", keyId: nil, midgarId: "id-fork"))
        let warning = try #require(harness.logs.warnings.first)
        #expect(warning.contains("minting a new identity"))
        for secret in ["CRED-SECRET-2", "CRED-FORK", "refresh-f", "id-fork", "id-shared"] {
            #expect(!harness.logs.all.contains { $0.contains(secret) })
        }
    }

    @Test func aForkedAttestedMintUsesANewKeyAndChallenge() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            challengeReply,
            .json(401, errorJSON("invalid_credential")),
            .json(200, #"{"challenge":"chal-2","expiresIn":300}"#),
            .json(201, sessionJSON(
                midgarId: "id-fork", accessToken: freshToken("app_attest"), refreshToken: "refresh-f",
                extra: ["credential": "CRED-FORK"]
            ))
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths.last == "POST /v1/identity/mint")
        #expect(bodyObject(harness.host.requests[3])["keyId"] as? String == "key-2")
        #expect(try harness.storedShared()?.midgarId == "id-fork")
        #expect(try harness.storedSession()?.keyId == "key-2")
    }

    @Test func aSharedItemThatCannotBeReadIsNeverOverwritten() async throws {
        let harness = try IdentityHarness(attested: false)
        try harness.keychain.write(Data(#"{"format":2}"#.utf8), to: .shared)

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .corruptSharedItem)
        #expect(harness.host.requests.isEmpty)
        #expect(try harness.keychain.read(.shared) == Data(#"{"format":2}"#.utf8))
    }

    @Test func anUnreadablePerAppItemIsRemovedAndRecoveredThroughAttach() async throws {
        let harness = try IdentityHarness(attested: false, shared: shared)
        try harness.keychain.write(Data("garbage".utf8), to: .session(appID: IdentityHarness.appID))
        harness.enqueue(attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/attach"])
        #expect(try harness.storedSession()?.refreshToken == "refresh-a")
    }

    @Test func aTransientAttachFailureLeavesTheSharedItemAndStoresNoSession() async throws {
        for reply in [StubReply.failing(.notConnectedToInternet), .json(503, errorJSON("down")), .json(429, errorJSON("rate_limited"))] {
            let harness = try IdentityHarness(attested: false, shared: shared)
            harness.enqueue(reply)

            let error = await thrownIdentityError { try await harness.identity.accessToken() }

            #expect(error?.isTransient == true)
            #expect(try harness.storedShared() == shared)
            #expect(try harness.storedSession() == nil)
        }
    }
}
