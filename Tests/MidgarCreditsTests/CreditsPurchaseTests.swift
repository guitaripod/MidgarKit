import Foundation
import Testing
import MidgarCommerce
import MidgarCore
@testable import MidgarCredits

@Suite struct CreditsPurchaseTests {
    @Test func buyingAPackBuysThenValidatesThenReadsTheBalance() async throws {
        let h = CreditsHarness()
        let receipt = creditsReceipt()
        h.store.queue(.purchased(receipt))
        h.gateway.script("validate", .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(156))
        let stream = await h.credits.events()

        let result = try await h.credits.buy("starter")
        await h.credits.stop()

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 156))
        #expect(h.store.purchased == [CreditsProducts.starter])
        #expect(h.gateway.requests.map(\.path) == [
            "/v1/intelligence/v1/credits/purchase/revenuecat/validate",
            "/v1/intelligence/v1/credits/balance"
        ])
        let validate = try #require(h.gateway.requests.first)
        #expect(validate.method == "POST")
        #expect(validate.headers["Authorization"] == "Bearer jwt-1")
        #expect(validate.headers["Content-Type"] == "application/json")
        #expect(validate.json["pack_id"] as? String == "starter")
        #expect(validate.json["purchase_token"] as? String == "1001")
        #expect(validate.json["product_id"] as? String == CreditsProducts.starter)
        #expect(validate.json["platform"] as? String == "ios")
        #expect(validate.json["signed_transaction"] as? String == "jws-1001")
        #expect(h.queuedFile.isEmpty)
        #expect(h.sleeper.requested.isEmpty)
        var events: [MidgarCreditsEvent] = []
        for await event in stream {
            events.append(event)
        }
        #expect(events == [
            .balanceChanged(MidgarCreditsBalance(credits: 156, updatedAt: creditsEpoch)),
            .purchaseCredited(packID: "starter", creditsAdded: 150)
        ])
    }

    @Test func aLegacyAppSendsBothCredentialsOnTheValidationToo() async throws {
        let h = CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        _ = try await h.credits.buy("starter")

        for request in h.gateway.requests {
            #expect(request.headers["Authorization"] == "Bearer mk_legacy_key")
            #expect(request.headers["X-Midgar-Token"] == "jwt-1")
        }
        #expect(h.gateway.requests.count == 2)
    }

    @Test func theValidationsOwnBalanceStandsInWhenTheConfirmingReadFails() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .credited(added: 150, newBalance: 160))
        h.gateway.script("balance", .walletUnavailable)

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 160))
        #expect(await h.credits.balance?.credits == 160)
    }

    @Test func validationIsRetriedWhileMakoWillCreditShortly() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditedShortly, .walletUnavailable, .notVerified, .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 150))
        #expect(h.gateway.requests(to: "validate").count == 4)
        #expect(h.sleeper.requested == [.seconds(2), .seconds(5), .seconds(15)])
        #expect(h.queuedFile.isEmpty)
        #expect(await h.credits.unconfirmedPurchases == 0)
    }

    @Test func aPurchaseStillUnconfirmedAfterTheRetriesStaysQueuedAndIsReportedPending() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditedShortly)

        let result = try await h.credits.buy("starter")

        #expect(result == .creditPending(packID: "starter", credits: 150))
        #expect(h.gateway.requests(to: "validate").count == 4)
        #expect(await h.credits.unconfirmedPurchases == 1)
        #expect(h.queuedFile.map(\.receipt.transactionID) == ["1001"])
        #expect(h.logs.lines.contains { $0.contains("1001") && !$0.contains("jws") })
    }

    @Test func refreshSettlesAQueuedPurchaseAndTheBalanceFollows() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditedShortly)
        _ = try await h.credits.buy("starter")
        h.gateway.script("validate", .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))
        let stream = await h.credits.events()

        let balance = try await h.credits.refresh()
        await h.credits.stop()

        #expect(balance.credits == 150)
        #expect(await h.credits.unconfirmedPurchases == 0)
        #expect(h.queuedFile.isEmpty)
        var events: [MidgarCreditsEvent] = []
        for await event in stream {
            events.append(event)
        }
        #expect(events.contains(.purchaseCredited(packID: "starter", creditsAdded: 150)))
        #expect(events.contains(.balanceChanged(MidgarCreditsBalance(credits: 150, updatedAt: creditsEpoch))))
    }

    @Test func aQueuedPurchaseSurvivesARelaunch() async throws {
        let first = CreditsHarness()
        first.store.queue(.purchased(creditsReceipt()))
        first.gateway.script("validate", .failing(.notConnectedToInternet))

        let result = try await first.credits.buy("starter")
        #expect(result == .creditPending(packID: "starter", credits: 150))
        await first.credits.stop()

        let second = first.relaunched()
        #expect(await second.credits.unconfirmedPurchases == 1)
        second.gateway.script("validate", .credited(added: 150, newBalance: 150))
        second.gateway.script("balance", .balance(150))
        _ = try await second.credits.refresh()

        #expect(second.queuedFile.isEmpty)
        let sent = second.gateway.requests(to: "validate").last
        #expect(sent?.json["purchase_token"] as? String == "1001")
    }

    @Test func aPurchaseQueuedInTheBackgroundIsRetriedUntilMakoConfirmsIt() async throws {
        let h = CreditsHarness(reconciles: true)
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditedShortly, .creditedShortly, .creditedShortly, .creditedShortly, .creditedShortly, .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        let result = try await h.credits.buy("starter")
        #expect(result == .creditPending(packID: "starter", credits: 150))

        #expect(await eventually { await h.credits.unconfirmedPurchases == 0 })
        #expect(await eventually { await h.credits.balance?.credits == 150 })
        #expect(h.sleeper.requested.contains(.seconds(30)))
        await h.credits.stop()
    }

    @Test func aPurchaseMakoAlreadyCreditedViaTheWebhookCountsAsCredited() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .alreadyProcessed)
        h.gateway.script("balance", .balance(300))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 300))
        #expect(h.gateway.requests(to: "validate").count == 1)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func aPurchaseMakoRefusesForGoodThrowsAndLeavesTheQueue() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(400, "bad_request", "product_id does not match pack_id"))

        await #expect(throws: MidgarCreditsError.purchaseRejected(message: "product_id does not match pack_id")) {
            try await h.credits.buy("starter")
        }
        #expect(h.gateway.requests(to: "validate").count == 1)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func insufficientCreditsOnTheValidationIsFinalToo() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(402, "insufficient_credits", "no"))
        h.gateway.script("balance", .balance(2))

        await #expect(throws: MidgarCreditsError.insufficientCredits(balance: 2)) {
            try await h.credits.buy("starter")
        }
        #expect(h.queuedFile.isEmpty)
    }

    @Test func cancelledAndApprovalPendingPurchasesTouchNothingElse() async throws {
        let h = CreditsHarness()
        h.store.queue(.cancelled)
        h.store.queue(.pending)

        #expect(try await h.credits.buy("starter") == .cancelled)
        #expect(try await h.credits.buy("plus") == .awaitingApproval)
        #expect(h.gateway.requests.isEmpty)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func unconfiguredPacksAndProductsAreNamedAndNothingIsBought() async throws {
        let empty = CreditsHarness(packs: [])
        await #expect(throws: MidgarCreditsError.notConfigured(.noPacks)) { try await empty.credits.buy("starter") }

        let h = CreditsHarness()
        await #expect(throws: MidgarCreditsError.notConfigured(.unknownPack("gold"))) { try await h.credits.buy("gold") }
        #expect(h.store.purchased.isEmpty)

        h.store.queue(failure: .unknownProduct(CreditsProducts.starter))
        await #expect(throws: MidgarCreditsError.notConfigured(.productNotSold(CreditsProducts.starter))) {
            try await h.credits.buy("starter")
        }

        h.store.queue(failure: .readOnly)
        await #expect(throws: MidgarCreditsError.notConfigured(.purchasesDisabled)) { try await h.credits.buy("starter") }

        h.store.queue(failure: .storeKit("boom"))
        await #expect(throws: MidgarCreditsError.store(.storeKit("boom"))) { try await h.credits.buy("starter") }
        #expect(h.gateway.requests.isEmpty)
    }

    @Test func aReceiptBoughtElsewhereIsRedeemedThroughTheSamePath() async throws {
        let h = CreditsHarness()
        h.gateway.script("validate", .credited(added: 700, newBalance: 700))
        h.gateway.script("balance", .balance(700))

        let result = try await h.credits.redeem(creditsReceipt(id: "2002", product: CreditsProducts.plus))

        #expect(result == .credited(packID: "plus", creditsAdded: 700, balance: 700))
        #expect(h.gateway.requests(to: "validate").first?.json["pack_id"] as? String == "plus")
        await #expect(throws: MidgarCreditsError.notConfigured(.productNotSold("other"))) {
            try await h.credits.redeem(creditsReceipt(id: "3", product: "other"))
        }
    }

    @Test func aQueuedPurchaseOlderThanAWeekIsDroppedNotRetriedForever() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditedShortly)
        _ = try await h.credits.buy("starter")
        let validations = h.gateway.requests(to: "validate").count
        h.gateway.script("balance", .balance(0))
        h.clock.advance(8 * 24 * 3600)

        _ = try await h.credits.refresh()

        #expect(h.gateway.requests(to: "validate").count == validations)
        #expect(await h.credits.unconfirmedPurchases == 0)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func aPurchaseApprovedLaterRefreshesTheBalance() async throws {
        let h = CreditsHarness(startsRefreshing: true)
        h.gateway.script("balance", .balance(10))
        #expect(await eventually { h.gateway.requests(to: "balance").count >= 1 })

        h.gateway.script("balance", .balance(160))
        h.store.emit(.purchaseApproved(productID: CreditsProducts.starter))

        #expect(await eventually { await h.credits.balance?.credits == 160 })
        await h.credits.stop()
    }

    @Test func aPurchaseApprovedForAnotherProductIsIgnored() async throws {
        let h = CreditsHarness(startsRefreshing: true)
        h.gateway.script("balance", .balance(10))
        #expect(await eventually { await h.credits.balance?.credits == 10 })
        let reads = h.gateway.requests(to: "balance").count

        h.store.emit(.purchaseApproved(productID: "app.midgar.test.pro"))
        h.store.emit(.entitlementsChanged)
        try await Task.sleep(for: .milliseconds(100))

        #expect(h.gateway.requests(to: "balance").count == reads)
        await h.credits.stop()
    }
}
