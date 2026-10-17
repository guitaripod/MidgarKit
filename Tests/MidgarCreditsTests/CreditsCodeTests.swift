import Foundation
import Testing
import MidgarCommerce
import MidgarCore
@testable import MidgarCredits

@Suite struct CreditsCodeTests {
    @Test func aCreditPendingCodeIsRetriedAndThenCredited() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditPending, .creditPending, .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 150))
        #expect(h.gateway.requests(to: "validate").count == 3)
        #expect(h.sleeper.requested == [.seconds(2), .seconds(5)])
        #expect(h.queuedFile.isEmpty)
    }

    @Test func aCreditPendingCodeIsRetriedWhateverTheTextSays() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(409, "credit_pending", "wording that no client matches"), .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 150))
        #expect(h.gateway.requests(to: "validate").count == 2)
    }

    @Test func aPurchaseThatStaysPendingIsReportedPendingAndKeptQueued() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .creditPending)

        let result = try await h.credits.buy("starter")

        #expect(result == .creditPending(packID: "starter", credits: 150))
        #expect(h.gateway.requests(to: "validate").count == 4)
        #expect(await h.credits.unconfirmedPurchases == 1)
    }

    @Test func anAlreadyProcessedCodeCountsAsCreditedWhateverTheTextSays() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(400, "already_processed", "this wording is not matched"))
        h.gateway.script("balance", .balance(300))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 300))
        #expect(h.gateway.requests(to: "validate").count == 1)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func anAlreadyProcessedCodeBeatsTextThatSaysTheOpposite() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(400, "already_processed", "Purchase could not be verified"))
        h.gateway.script("balance", .balance(300))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 300))
    }

    @Test func anUnverifiablePurchaseCodeIsRetriedWhateverTheTextSays() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(400, "unverifiable_purchase", "unmatched wording"), .credited(added: 150, newBalance: 150))
        h.gateway.script("balance", .balance(150))

        let result = try await h.credits.buy("starter")

        #expect(result == .credited(packID: "starter", creditsAdded: 150, balance: 150))
        #expect(h.gateway.requests(to: "validate").count == 2)
    }

    @Test func aRefusalWithAnotherCodeIsFinalEvenWhenItsTextLooksRetryable() async throws {
        let h = CreditsHarness()
        h.store.queue(.purchased(creditsReceipt()))
        h.gateway.script("validate", .refused(403, "forbidden", "The transaction was not made by this Midgar ID."))

        await #expect(throws: MidgarCreditsError.purchaseRejected(message: "The transaction was not made by this Midgar ID.")) {
            try await h.credits.buy("starter")
        }
        #expect(h.gateway.requests(to: "validate").count == 1)
        #expect(h.queuedFile.isEmpty)
    }

    @Test func aCodelessMakoIsStillUnderstoodByStatusAndText() {
        let processed = MidgarCreditsError.server(status: 400, code: nil, message: "Purchase has already been processed")
        let unverified = MidgarCreditsError.server(status: 400, code: "bad_request", message: "Purchase could not be verified with RevenueCat")
        let masked = MidgarCreditsError.server(status: 500, code: "internal_error", message: "An internal error occurred.")
        let final = MidgarCreditsError.server(status: 400, code: "bad_request", message: "product_id does not match pack_id")
        #expect(MidgarCredits.classify(processed) == .alreadyProcessed)
        #expect(MidgarCredits.classify(unverified) == .retry(unverified))
        #expect(MidgarCredits.classify(masked) == .retry(masked))
        #expect(MidgarCredits.classify(final) == .rejected(.purchaseRejected(message: "product_id does not match pack_id")))
    }

    @Test func theCodesDecideBeforeTheStatus() {
        let pending = MidgarCreditsError.server(status: 409, code: "credit_pending", message: "x")
        let processed = MidgarCreditsError.server(status: 409, code: "already_processed", message: "x")
        let conflict = MidgarCreditsError.server(status: 409, code: "conflict", message: "x")
        #expect(MidgarCredits.classify(pending) == .retry(pending))
        #expect(MidgarCredits.classify(processed) == .alreadyProcessed)
        #expect(MidgarCredits.classify(conflict) == .rejected(.purchaseRejected(message: "x")))
    }
}
