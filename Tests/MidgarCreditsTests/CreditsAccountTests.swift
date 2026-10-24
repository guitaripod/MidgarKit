import Foundation
import Testing
import MidgarCore
@testable import MidgarCredits

@Suite struct CreditsAccountTests {
    private func harness() -> CreditsHarness {
        CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
    }

    @Test func deletingSendsTheDeleteWithTheLegacyKeyAsTheOnlyCredential() async throws {
        let h = harness()
        h.gateway.script("identity", .json(200, #"{"deleted":true}"#))

        try await h.credits.deleteLegacyAccount()

        let request = try #require(h.gateway.requests.first)
        #expect(h.gateway.requests.count == 1)
        #expect(request.method == "DELETE")
        #expect(request.path == "/v1/intelligence/v1/identity")
        #expect(request.headers["Authorization"] == "Bearer mk_legacy_key")
        #expect(request.headers["X-Midgar-Token"] == nil)
        #expect(request.headers["X-App-ID"] == "app-test")
    }

    @Test(arguments: [200, 204, 401, 404])
    func theseStatusesMeanTheAccountIsGone(status: Int) async throws {
        let h = harness()
        h.gateway.script("identity", .json(status, status == 204 ? "" : #"{"error":{"message":"gone","type":"x","param":null,"code":"gone"}}"#))

        try await h.credits.deleteLegacyAccount()

        #expect(h.gateway.requests.count == 1)
    }

    @Test func aServerErrorThrowsTheTypedErrorAndSendsOneRequest() async throws {
        let h = harness()
        h.gateway.script("identity", .refused(500, "internal_error", "boom"))

        await #expect(throws: MidgarCreditsError.server(status: 500, code: "internal_error", message: "boom")) {
            try await h.credits.deleteLegacyAccount()
        }
        #expect(h.gateway.requests.count == 1)
    }

    @Test func anUnavailableWalletRateLimitingAndTheNetworkAreTyped() async throws {
        let h = harness()

        h.gateway.script("identity", .walletUnavailable)
        await #expect(throws: MidgarCreditsError.walletUnavailable) { try await h.credits.deleteLegacyAccount() }

        h.gateway.script("identity", .refused(429, "rate_limit_exceeded", "Rate limit exceeded"))
        await #expect(throws: MidgarCreditsError.rateLimited(retryAfter: nil)) { try await h.credits.deleteLegacyAccount() }

        h.gateway.script("identity", .failing(.notConnectedToInternet))
        await #expect(throws: MidgarCreditsError.offline) { try await h.credits.deleteLegacyAccount() }

        h.gateway.script("identity", .json(403, "{}"))
        await #expect(throws: MidgarCreditsError.server(status: 403, code: nil, message: "HTTP 403")) {
            try await h.credits.deleteLegacyAccount()
        }
    }

    @Test func withoutALegacyKeyNothingIsSent() async throws {
        let none = CreditsHarness()
        let nilKey = CreditsHarness(legacyAPIKey: { nil })
        let emptyKey = CreditsHarness(legacyAPIKey: { "" })

        for h in [none, nilKey, emptyKey] {
            try await h.credits.deleteLegacyAccount()
            #expect(h.gateway.requests.isEmpty)
        }
    }

    @Test func aDeletionDoesNotNeedAMidgarToken() async throws {
        let h = harness()
        h.identity.set(nil)
        h.gateway.script("identity", .json(200, #"{"deleted":true}"#))

        try await h.credits.deleteLegacyAccount()

        #expect(h.gateway.requests.count == 1)
    }

    @Test func theKnownBalanceIsForgottenOnceTheAccountIsGoneButNotWhenItFails() async throws {
        let h = harness()
        h.gateway.script("balance", .balance(9))
        _ = try await h.credits.refresh()

        h.gateway.script("identity", .refused(500, "internal_error", "boom"))
        _ = try? await h.credits.deleteLegacyAccount()
        #expect(await h.credits.balance?.credits == 9)

        h.gateway.script("identity", .json(200, #"{"deleted":true}"#))
        try await h.credits.deleteLegacyAccount()
        #expect(await h.credits.balance == nil)
    }
}
