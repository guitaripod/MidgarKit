import Foundation
import Testing
import MidgarCommerce
import MidgarCore
@testable import MidgarCredits

@Suite struct CreditsReadTests {
    @Test func theBalanceIsReadThroughTheGatewayWithTheMidgarIdAsTheOnlyCredential() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .balance(42))
        let stream = await h.credits.events()

        let balance = try await h.credits.refresh()
        await h.credits.stop()

        #expect(balance.credits == 42)
        #expect(await h.credits.balance?.credits == 42)
        let request = try #require(h.gateway.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/v1/intelligence/v1/credits/balance")
        #expect(request.headers["Authorization"] == "Bearer jwt-1")
        #expect(request.headers["X-Midgar-Token"] == nil)
        #expect(request.headers["X-App-ID"] == "app-test")
        var events: [MidgarCreditsEvent] = []
        for await event in stream {
            events.append(event)
        }
        #expect(events == [.balanceChanged(MidgarCreditsBalance(credits: 42, updatedAt: creditsEpoch))])
    }

    @Test func aLegacyKeySendsItselfAsTheBearerAndTheMidgarTokenBesideIt() async throws {
        let h = CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
        h.gateway.script("balance", .balance(7))

        _ = try await h.credits.refresh()

        let request = try #require(h.gateway.requests.first)
        #expect(request.headers["Authorization"] == "Bearer mk_legacy_key")
        #expect(request.headers["X-Midgar-Token"] == "jwt-1")
        #expect(request.headers["X-App-ID"] == "app-test")
    }

    @Test func aLegacyKeyClosureThatReturnsNothingMeansANativeRequest() async throws {
        let h = CreditsHarness(legacyAPIKey: { nil })
        h.gateway.script("balance", .balance(7))

        _ = try await h.credits.refresh()

        let request = try #require(h.gateway.requests.first)
        #expect(request.headers["Authorization"] == "Bearer jwt-1")
        #expect(request.headers["X-Midgar-Token"] == nil)
    }

    @Test func aLegacyRequestWithoutATokenFailsInsteadOfSendingTheKeyAlone() async throws {
        let h = CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
        h.identity.set(nil)

        await #expect(throws: MidgarCreditsError.identityUnavailable) {
            try await h.credits.refresh()
        }
        #expect(h.gateway.requests.isEmpty)
    }

    @Test func aNativeRequestWithoutATokenFailsWithTheIdentityError() async throws {
        let h = CreditsHarness()
        h.identity.set(nil)

        await #expect(throws: MidgarCreditsError.identityUnavailable) {
            try await h.credits.refresh()
        }
        #expect(h.gateway.requests.isEmpty)
    }

    @Test func transactionsAreReadAsOnePageWithBothDateFormats() async throws {
        let h = CreditsHarness()
        h.gateway.script("transactions", .json(200, """
        {"transactions":[
          {"id":"wallet:9","user_id":"u","type":"purchase","amount":150,"balance_after":156,"description":"Starter pack","reference_id":"tx:1001","created_at":"2026-10-17T12:00:00+00:00"},
          {"id":"c-1","user_id":"u","type":"spend","amount":-6,"balance_after":6,"description":"Chat","reference_id":null,"created_at":"2026-10-01 08:30:00"},
          {"id":"c-0","user_id":"u","type":"bonus","amount":12,"balance_after":12,"description":"Welcome bonus","reference_id":null,"created_at":"soon"}
        ],"total":120,"limit":3,"offset":0,"page":1,"per_page":3}
        """))

        let page = try await h.credits.transactions(page: 1, perPage: 3)

        #expect(page.total == 120)
        #expect(page.hasMore)
        #expect(page.transactions.map(\.id) == ["wallet:9", "c-1", "c-0"])
        #expect(page.transactions[0].kind == "purchase")
        #expect(page.transactions[0].amount == 150)
        #expect(page.transactions[0].balanceAfter == 156)
        #expect(page.transactions[0].reference == "tx:1001")
        #expect(page.transactions[0].date == Date(timeIntervalSince1970: 1_792_238_400))
        #expect(page.transactions[1].amount == -6)
        #expect(page.transactions[1].reference == nil)
        #expect(page.transactions[1].date == Date(timeIntervalSince1970: 1_790_843_400))
        #expect(page.transactions[2].date == nil)
        let request = try #require(h.gateway.requests.first)
        #expect(request.path == "/v1/intelligence/v1/credits/transactions")
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "page" }?.value == "1")
        #expect(query.first { $0.name == "per_page" }?.value == "3")
    }

    @Test func aPageSizeAboveTheServersCapIsClamped() async throws {
        let h = CreditsHarness()
        h.gateway.script("transactions", .json(200, #"{"transactions":[],"total":0}"#))

        let page = try await h.credits.transactions(page: 0, perPage: 500)

        let query = URLComponents(url: try #require(h.gateway.requests.first).url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "page" }?.value == "1")
        #expect(query.first { $0.name == "per_page" }?.value == "100")
        #expect(page.perPage == 100)
        #expect(!page.hasMore)
    }

    @Test func offersJoinThePacksWithWhatTheStoreSells() async throws {
        let h = CreditsHarness()
        h.store.setCatalog([StoreProduct(id: CreditsProducts.starter, displayName: "Starter", description: "", displayPrice: "$2.99")])

        let offers = try await h.credits.offers()

        #expect(offers.map(\.id) == ["starter"])
        #expect(offers.first?.product.displayPrice == "$2.99")
        #expect(offers.first?.pack.credits == 150)
    }

    @Test func theWalletBeingUnavailableIsOneRequestAndOneTypedError() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .walletUnavailable)

        await #expect(throws: MidgarCreditsError.walletUnavailable) {
            try await h.credits.refresh()
        }
        #expect(h.gateway.requests(to: "balance").count == 1)
    }

    @Test func offlineAndTimeoutsAreTheOfflineCase() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .failing(.notConnectedToInternet))
        await #expect(throws: MidgarCreditsError.offline) { try await h.credits.refresh() }

        h.gateway.script("balance", .failing(.timedOut))
        await #expect(throws: MidgarCreditsError.offline) { try await h.credits.refresh() }
    }

    @Test func aRejectedSessionAndRateLimitingAreTyped() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .refused(401, "unauthorized", "Invalid API key"))
        await #expect(throws: MidgarCreditsError.unauthorized) { try await h.credits.refresh() }

        h.gateway.script("balance", .refused(429, "rate_limit_exceeded", "Rate limit exceeded"))
        await #expect(throws: MidgarCreditsError.rateLimited(retryAfter: nil)) { try await h.credits.refresh() }

        h.gateway.script("balance", .refused(500, "internal_error", "boom"))
        await #expect(throws: MidgarCreditsError.server(status: 500, code: "internal_error", message: "boom")) {
            try await h.credits.refresh()
        }

        h.gateway.script("balance", .json(200, "not json"))
        await #expect(throws: MidgarCreditsError.invalidResponse) { try await h.credits.refresh() }
    }

    @Test func insufficientCreditsCarriesTheWalletBalance() async throws {
        let h = CreditsHarness()
        h.gateway.script("transactions", .refused(402, "insufficient_credits", "Insufficient credits. Need 6 credits, have 5"))
        h.gateway.script("balance", .balance(5))

        await #expect(throws: MidgarCreditsError.insufficientCredits(balance: 5)) {
            try await h.credits.transactions()
        }
        #expect(h.gateway.requests(to: "balance").count == 1)
    }

    @Test func insufficientCreditsHasNoBalanceWhenTheReadFailsToo() async throws {
        let h = CreditsHarness()
        h.gateway.script("transactions", .refused(402, "insufficient_credits", "Insufficient credits"))
        h.gateway.script("balance", .refused(402, "insufficient_credits", "Insufficient credits"))

        await #expect(throws: MidgarCreditsError.insufficientCredits(balance: nil)) {
            try await h.credits.transactions()
        }
        #expect(h.gateway.requests(to: "balance").count == 1)
    }

    @Test func aMeteredCallsPaymentRequiredIsMappedWithTheBalance() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .balance(3))

        let mapped = await h.credits.creditsError(for: .paymentRequired(code: "insufficient_credits"))
        let offline = await h.credits.creditsError(for: .offline)
        let cancelled = await h.credits.creditsError(for: .cancelled)

        #expect(mapped as? MidgarCreditsError == .insufficientCredits(balance: 3))
        #expect(offline as? MidgarCreditsError == .offline)
        #expect(cancelled is CancellationError)
    }

    @Test func everyErrorHasAUserFacingDescription() {
        let errors: [MidgarCreditsError] = [
            .offline, .insufficientCredits(balance: 1), .walletUnavailable, .notConfigured(.noPacks), .unauthorized,
            .identityUnavailable, .rateLimited(retryAfter: 1), .purchaseRejected(message: "m"),
            .store(.readOnly), .server(status: 500, code: nil, message: "m"), .invalidResponse
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
