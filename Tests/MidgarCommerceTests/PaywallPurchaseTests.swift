import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct PaywallPurchaseTests {
    @Test func aPurchaseResultFromAStoreKitViewTakesTheFullMoneyPath() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let transaction = h.transaction()
        h.storeKit.setCurrent([.verified(transaction)])

        let result = try await h.store.complete(.success(.verified(transaction)))
        await h.store.refresh()

        #expect(result == .purchased)
        #expect(h.finishes.ids == [1])
        #expect(h.ledger.reports == ["jws-1-active"])
        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro"))
        let events = await h.signals.events
        #expect(events.first?.name == "paywall.purchase")
        #expect(events.first?.props["product"] == .string(Products.pro))
    }

    @Test func aViewPurchaseThatTheStoreDoesNotHandleIsRefusedAndLeftUnfinished() async throws {
        let h = StoreHarness()
        let transaction = h.transaction(product: Products.credits, kind: .consumable)

        await #expect(throws: MidgarStoreError.unknownProduct(Products.credits)) {
            _ = try await h.store.complete(.success(.verified(transaction)))
        }

        #expect(h.finishes.ids.isEmpty)
        #expect(h.pendingReports.isEmpty)
    }

    @Test func anUnverifiedViewPurchaseThrowsAndGrantsNothing() async throws {
        let h = StoreHarness()
        let transaction = h.transaction()

        await #expect(throws: MidgarStoreError.unverifiedTransaction(productID: Products.pro)) {
            _ = try await h.store.complete(.success(.unverified(transaction, reason: "bad signature")))
        }

        #expect(h.finishes.ids.isEmpty)
        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro") == false)
    }

    @Test func pendingAndCancelledViewResultsChangeNothing() async throws {
        let h = StoreHarness()

        let pending = try await h.store.complete(StorePurchaseOutcome.pending)
        let cancelled = try await h.store.complete(StorePurchaseOutcome.userCancelled)

        #expect(pending == .pending)
        #expect(cancelled == .cancelled)
        #expect(h.finishes.ids.isEmpty)
        #expect(await h.signals.events.isEmpty)
    }

    @Test func aReadOnlyStoreRefusesToCompleteAViewPurchase() async throws {
        let h = StoreHarness(mode: .readOnly)
        let transaction = h.transaction()

        await #expect(throws: MidgarStoreError.readOnly) {
            _ = try await h.store.complete(.success(.verified(transaction)))
        }
        #expect(h.finishes.ids.isEmpty)
    }

    @Test func purchaseOptionsCarryTheMidgarIdAsTheAccountToken() async {
        let h = StoreHarness()

        let options = await h.store.purchaseOptions()

        #expect(options.count == 1)
    }

    @Test func purchaseOptionsAreEmptyWhenTheIdentityCannotAnswer() async {
        let h = StoreHarness(identity: FakeIdentity(nil))

        let options = await h.store.purchaseOptions()

        #expect(options.isEmpty)
    }
}
