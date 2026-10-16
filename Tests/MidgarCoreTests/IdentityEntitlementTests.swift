import Foundation
import Testing
@testable import MidgarCore

/// A keychain that behaves like an app without the shared access group: every shared-slot call fails with `errSecMissingEntitlement`. It has no state of its own; the base keychain locks its own.
final class MissingEntitlementKeychain: MidgarKeychain, @unchecked Sendable {
    let base: MidgarInMemoryKeychain
    private let status: Int32

    init(base: MidgarInMemoryKeychain, status: Int32 = -34018) {
        self.base = base
        self.status = status
    }

    func read(_ slot: MidgarKeychainSlot) throws -> Data? {
        try guarded(slot) { try base.read(slot) }
    }

    func write(_ data: Data, to slot: MidgarKeychainSlot) throws {
        try guarded(slot) { try base.write(data, to: slot) }
    }

    func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool {
        try guarded(slot) { try base.writeIfAbsent(data, to: slot) }
    }

    func delete(_ slot: MidgarKeychainSlot) throws {
        try guarded(slot) { try base.delete(slot) }
    }

    private func guarded<Value>(_ slot: MidgarKeychainSlot, _ body: () throws -> Value) throws -> Value {
        if slot == .shared {
            throw MidgarKeychainError(status: status)
        }
        return try body()
    }
}

@Suite struct IdentityEntitlementTests {
    private func harness(status: Int32 = -34018) throws -> IdentityHarness {
        try IdentityHarness(attested: false, keychainOverride: { MissingEntitlementKeychain(base: $0, status: status) })
    }

    @Test func aMissingEntitlementFallsBackToAnAppLocalItemAndKeepsWorking() async throws {
        let harness = try harness()
        harness.enqueue(
            .json(201, sessionJSON(
                midgarId: "id-local", accessToken: freshToken(), refreshToken: "r1", extra: ["credential": "CRED-LOCAL"]
            )),
            .json(200, sessionJSON(midgarId: "id-local", accessToken: freshToken("development"), refreshToken: "r2"))
        )

        let first = try await harness.identity.accessToken()
        harness.clock.advance(4000)
        let second = try await harness.identity.accessToken()

        #expect(first == freshToken())
        #expect(second == freshToken("development"))
        #expect(harness.paths == ["POST /v1/identity/mint/unverified", "POST /v1/identity/refresh"])
        let local = try #require(try harness.keychain.read(.local(appID: IdentityHarness.appID)))
        #expect(try JSONDecoder().decode(SharedIdentity.self, from: local) == SharedIdentity(midgarId: "id-local", credential: "CRED-LOCAL"))
        #expect(try harness.keychain.read(.shared) == nil)
    }

    @Test func theFallbackIsLoggedOnce() async throws {
        let harness = try harness()
        harness.enqueue(
            .json(201, sessionJSON(midgarId: "id-local", accessToken: freshToken(), refreshToken: "r1", extra: ["credential": "C"])),
            .json(200, sessionJSON(midgarId: "id-local", accessToken: freshToken(), refreshToken: "r2")),
            .json(200, sessionJSON(midgarId: "id-local", accessToken: freshToken(), refreshToken: "r3"))
        )

        _ = try await harness.identity.accessToken()
        harness.clock.advance(4000)
        _ = try await harness.identity.accessToken()
        harness.clock.advance(4000)
        _ = try await harness.identity.accessToken()

        let fallbackLines = harness.logs.warnings.filter { $0.contains("entitlement") }
        #expect(fallbackLines.count == 1)
        #expect(!harness.logs.all.contains { $0.contains("CRED") })
    }

    @Test func aLaterRunFindsTheAppLocalIdentity() async throws {
        let first = try harness()
        first.enqueue(.json(201, sessionJSON(
            midgarId: "id-local", accessToken: freshToken(), refreshToken: "r1", extra: ["credential": "CRED-LOCAL"]
        )))
        _ = try await first.identity.accessToken()
        try first.keychain.delete(.session(appID: IdentityHarness.appID))

        let second = MidgarIdentity(
            appID: IdentityHarness.appID,
            bundleID: IdentityHarness.bundleID,
            http: makeStubClient(first.host),
            keychain: MissingEntitlementKeychain(base: first.keychain),
            attestation: FakeAttestation(supported: false),
            clock: { first.clock.now },
            log: MidgarIdentityLogger(info: { _ in }, warning: { _ in })
        )
        first.enqueue(.json(200, sessionJSON(midgarId: "id-local", accessToken: freshToken(), refreshToken: "r9")))

        _ = try await second.accessToken()

        #expect(first.paths.last == "POST /v1/identity/attach")
        #expect(bodyObject(first.host.requests.last!)["credential"] as? String == "CRED-LOCAL")
    }

    @Test func otherKeychainFailuresStillSurface() async throws {
        let harness = try harness(status: -25308)

        let error = await thrownIdentityError { try await harness.identity.accessToken() }

        #expect(error == .keychain(status: -25308))
        #expect(harness.host.requests.isEmpty)
    }
}
