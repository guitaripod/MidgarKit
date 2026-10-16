import Foundation
import Testing
@testable import MidgarCore

private let credential = "CRED-SECRET-1"

private func mintReply(_ id: String = "id-minted", tier: String = "unverified", refresh: String = "refresh-1") -> StubReply {
    .json(201, sessionJSON(midgarId: id, accessToken: freshToken(tier), refreshToken: refresh, extra: ["credential": credential]))
}

@Suite struct IdentityMintTests {
    @Test func mintsUnverifiedWhenNothingIsStoredAndAppAttestIsUnsupported() async throws {
        let harness = try IdentityHarness(attested: false)
        harness.enqueue(mintReply())

        let token = try await harness.identity.accessToken()

        #expect(token == freshToken())
        #expect(harness.paths == ["POST /v1/identity/mint/unverified"])
        #expect(bodyObject(harness.host.requests[0]) as? [String: String] == ["bundleId": IdentityHarness.bundleID])
        #expect(try harness.storedShared() == SharedIdentity(midgarId: "id-minted", credential: credential))
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-1", keyId: nil, midgarId: "id-minted"))
        #expect(harness.attestation.keys.isEmpty)
        #expect(try await harness.identity.tier == .unverified)
    }

    @Test func mintsWithAttestationWhenSupported() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.enqueue(
            .json(200, #"{"challenge":"chal-1","expiresIn":300}"#),
            mintReply(tier: "app_attest")
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/mint"])
        let body = bodyObject(harness.host.requests[1])
        #expect(body["keyId"] as? String == "key-1")
        #expect(body["challenge"] as? String == "chal-1")
        #expect(body["bundleId"] as? String == IdentityHarness.bundleID)
        #expect(body["attestation"] as? String == Data("attestation-of-key-1".utf8).base64EncodedString())
        let attested = try #require(harness.attestation.attestations.first)
        #expect(attested.hash == MidgarDigest.sha256(Data("chal-1".utf8)))
        #expect(try harness.storedSession()?.keyId == "key-1")
        #expect(try await harness.identity.tier == .appAttest)
    }

    @Test func unsupportedErrorFromAppAttestFallsBackToUnverifiedMint() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.attestation.failGenerate(with: .unsupported)
        harness.enqueue(.json(200, #"{"challenge":"chal-1","expiresIn":300}"#), mintReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/mint/unverified"])
        #expect(try harness.storedSession()?.keyId == nil)
    }

    @Test func appleAttestationOutageThrowsAndStoresNothing() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.attestation.failAttest(with: .unavailable)
        harness.enqueue(.json(200, #"{"challenge":"chal-1","expiresIn":300}"#))

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .attestation(.unavailable))
        #expect(error?.isTransient == true)
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
    }

    @Test func anotherAppWinningTheSharedItemRaceMakesThisAppAttachToIt() async throws {
        let rival = SharedIdentity(midgarId: "id-rival", credential: "CRED-RIVAL")
        let harness = try IdentityHarness(attested: false) { base in
            try RacingKeychain(base: base, rival: rival)
        }
        harness.enqueue(
            mintReply(),
            .json(200, sessionJSON(midgarId: "id-rival", accessToken: freshToken(), refreshToken: "refresh-rival"))
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/mint/unverified", "POST /v1/identity/attach"])
        let body = bodyObject(harness.host.requests[1])
        #expect(body["midgarId"] as? String == "id-rival")
        #expect(body["credential"] as? String == "CRED-RIVAL")
        #expect(try harness.storedShared() == rival)
        #expect(try harness.storedSession()?.midgarId == "id-rival")
    }

    @Test func mintFailureStoresNothing() async throws {
        let harness = try IdentityHarness(attested: false)
        harness.enqueue(.json(503, errorJSON("unavailable")))

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error?.isTransient == true)
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
    }

    @Test func midgarIdComesFromTheStoredSessionWithoutANetworkCall() async throws {
        let session = StoredSession(refreshToken: "r", keyId: nil, midgarId: "id-stored")
        let harness = try IdentityHarness(session: session)

        let id = try await harness.identity.midgarId

        #expect(id == "id-stored")
        #expect(harness.host.requests.isEmpty)
    }
}

/// The identity error an operation throws, or nil when it succeeds.
func thrownIdentityError<Value>(_ operation: () async throws -> Value) async -> MidgarIdentityError? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return error as? MidgarIdentityError
    }
}
