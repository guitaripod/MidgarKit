import Foundation
import Testing
@testable import MidgarCore

private let shared = SharedIdentity(midgarId: "id-shared", credential: "CRED-SECRET-3")

private let challenge1 = StubReply.json(200, #"{"challenge":"chal-1","expiresIn":300}"#)

private let challenge2 = StubReply.json(200, #"{"challenge":"chal-2","expiresIn":300}"#)

private func mintReply(tier: String = "unverified") -> StubReply {
    .json(201, sessionJSON(midgarId: "id-minted", accessToken: freshToken(tier), refreshToken: "refresh-m", extra: ["credential": "CRED-NEW"]))
}

private func attachReply(refresh: String = "refresh-a") -> StubReply {
    .json(200, sessionJSON(midgarId: "id-shared", accessToken: freshToken(), refreshToken: refresh))
}

@Suite struct IdentityAttestationFallbackTests {
    @Test(arguments: [MidgarAttestationError.failed, .invalidKey, .unsupported])
    func aKeyGenerationFailureMintsUnverified(error: MidgarAttestationError) async throws {
        let harness = try IdentityHarness(attested: true)
        harness.attestation.failGenerate(with: error)
        harness.enqueue(challenge1, mintReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/mint/unverified"])
        #expect(try harness.storedSession()?.keyId == nil)
        #expect(try harness.storedShared()?.midgarId == "id-minted")
        #expect(harness.attestation.keys.isEmpty)
        #expect(harness.logs.warnings.contains { $0.contains("App Attest failed") })
    }

    @Test func anAttestationFailureNamesItsKindInTheLogAndMintsUnverified() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.attestation.failAttest(with: .failed)
        harness.enqueue(challenge1, mintReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == ["POST /v1/identity/challenge", "POST /v1/identity/mint/unverified"])
        #expect(harness.logs.warnings.contains { $0.contains("App Attest failed (failed)") })
        #expect(try await harness.identity.tier == .unverified)
    }

    @Test func aServerRejectionOfTheAttestationRunsTheMintOnceMoreUnattested() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.enqueue(challenge1, .json(401, errorJSON("attestation_invalid")), mintReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/mint", "POST /v1/identity/mint/unverified"
        ])
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-m", keyId: nil, midgarId: "id-minted"))
        #expect(harness.logs.warnings.contains { $0.contains("attestation_invalid") })
    }

    @Test func aServerRejectionOfTheAttestationAttachesOnceMoreUnattested() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(challenge1, .json(401, errorJSON("attestation_invalid")), attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/attach", "POST /v1/identity/attach"
        ])
        #expect(bodyObject(harness.host.requests[1])["keyId"] as? String == "key-1")
        let second = bodyObject(harness.host.requests[2])
        #expect(second["keyId"] == nil)
        #expect(second["attestation"] == nil)
        #expect(second["challenge"] == nil)
        #expect(second["credential"] as? String == "CRED-SECRET-3")
        #expect(try harness.storedSession() == StoredSession(refreshToken: "refresh-a", keyId: nil, midgarId: "id-shared"))
    }

    @Test func aRetryableCodeStillRetriesWithNewEvidenceBeforeAnyFallback() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(challenge1, .json(409, errorJSON("key_already_attested")), challenge2, attachReply())

        _ = try await harness.identity.accessToken()

        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/attach",
            "POST /v1/identity/challenge", "POST /v1/identity/attach"
        ])
        #expect(bodyObject(harness.host.requests[3])["keyId"] as? String == "key-2")
        #expect(try harness.storedSession()?.keyId == "key-2")
    }

    @Test func aRejectionAfterTheRetryFallsBackUnattested() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            challenge1, .json(409, errorJSON("key_already_attested")),
            challenge2, .json(401, errorJSON("attestation_invalid")),
            attachReply()
        )

        _ = try await harness.identity.accessToken()

        #expect(harness.paths.count == 5)
        #expect(bodyObject(harness.host.requests[4])["keyId"] == nil)
        #expect(try harness.storedSession()?.keyId == nil)
    }

    @Test(arguments: [(503, "unavailable"), (429, "rate_limited"), (400, "app_mismatch"), (401, "invalid_credential")])
    func errorsThatAreNotAboutTheAttestationStillThrow(status: Int, code: String) async throws {
        let harness = try IdentityHarness(attested: true)
        harness.enqueue(challenge1, .json(status, errorJSON(code)))

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error != nil)
        #expect(harness.paths.last == "POST /v1/identity/mint")
        #expect(!harness.paths.contains("POST /v1/identity/mint/unverified"))
        #expect(try harness.storedShared() == nil)
        #expect(try harness.storedSession() == nil)
    }

    @Test func aFailedChallengeRequestStillThrows() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.enqueue(.json(503, errorJSON("unavailable")))

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error?.isTransient == true)
        #expect(harness.attestation.keys.isEmpty)
    }

    @Test func aClientFailureStopsKeyGenerationForTheRestOfTheProcess() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.attestation.failGenerate(with: .failed)
        harness.enqueue(challenge1, attachReply(refresh: "refresh-1"), attachReply(refresh: "refresh-2"))

        _ = try await harness.identity.accessToken()
        harness.attestation.failGenerate(with: nil)
        try harness.store.deleteSession()
        await harness.identity.dropCachedSession()
        _ = try await harness.identity.accessToken()

        #expect(harness.paths == [
            "POST /v1/identity/challenge", "POST /v1/identity/attach", "POST /v1/identity/attach"
        ])
        #expect(harness.attestation.keys.isEmpty)
        #expect(bodyObject(harness.host.requests[2])["keyId"] == nil)
        #expect(try harness.storedSession()?.refreshToken == "refresh-2")
    }

    @Test func aServerRejectionStopsKeyGenerationForTheRestOfTheProcess() async throws {
        let harness = try IdentityHarness(attested: true, shared: shared)
        harness.enqueue(
            challenge1, .json(401, errorJSON("attestation_invalid")), attachReply(refresh: "refresh-1"),
            attachReply(refresh: "refresh-2")
        )

        _ = try await harness.identity.accessToken()
        try harness.store.deleteSession()
        await harness.identity.dropCachedSession()
        _ = try await harness.identity.accessToken()

        #expect(harness.attestation.keys == ["key-1"])
        #expect(harness.paths.filter { $0 == "POST /v1/identity/challenge" }.count == 1)
        #expect(harness.logs.info.contains { $0.contains("failed earlier in this process") })
    }

    @Test func aNewProcessTriesAppAttestAgain() async throws {
        let first = try IdentityHarness(attested: true)
        first.attestation.failGenerate(with: .failed)
        first.enqueue(challenge1, mintReply())
        _ = try await first.identity.accessToken()

        let second = try IdentityHarness(attested: true)
        second.enqueue(challenge1, mintReply(tier: "app_attest"))
        _ = try await second.identity.accessToken()

        #expect(second.paths == ["POST /v1/identity/challenge", "POST /v1/identity/mint"])
        #expect(second.attestation.keys == ["key-1"])
    }

    @Test func appleAttestationBeingUnreachableIsNotRememberedAsAFailure() async throws {
        let harness = try IdentityHarness(attested: true)
        harness.attestation.failAttest(with: .unavailable)
        harness.enqueue(challenge1, challenge2, mintReply(tier: "app_attest"))

        _ = await thrownIdentityError { try await harness.identity.accessToken() }
        harness.attestation.failAttest(with: nil)
        _ = try await harness.identity.accessToken()

        #expect(harness.paths.last == "POST /v1/identity/mint")
        #expect(try harness.storedSession()?.keyId == "key-2")
    }
}
