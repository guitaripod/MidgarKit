import Foundation
import Testing
import MidgarCore
#if os(macOS)
import AppKit
#endif
@testable import MidgarCommerce

@Suite struct PurchaseTests {
    @Test func purchasePassesTheMidgarIdAsAccountToken() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])

        let result = try await h.store.purchase(Products.pro)
        await h.store.refresh()

        #expect(result == .purchased)
        #expect(h.storeKit.purchases.count == 1)
        #expect(h.storeKit.purchases.first?.productID == Products.pro)
        #expect(h.storeKit.purchases.first?.token == UUID(uuidString: FakeIdentity.first))
        #expect(h.finishes.ids == [1])
        #expect(h.ledger.reports == ["jws-1-active"])
        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro"))
        let events = await h.signals.events
        #expect(events.count == 1)
        #expect(events.first?.name == "paywall.purchase")
        #expect(events.first?.props["product"] == .string(Products.pro))
    }

    @Test func purchaseWithoutAnIdentityProceedsAndIsReportedForAttributionOnceOneExists() async throws {
        let identity = FakeIdentity(nil)
        let h = StoreHarness(identity: identity)
        let transaction = h.transaction(token: nil)
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])

        let result = try await h.store.purchase(Products.pro)
        await h.store.refresh()

        #expect(result == .purchased)
        #expect(h.storeKit.purchases.first?.token == nil)
        #expect(h.finishes.ids == [1])
        #expect(await h.store.isEntitled(to: "pro"))
        #expect(h.pendingReports.count == 1)
        #expect(h.ledger.reports.isEmpty)
        #expect(h.ledger.entitlementQueries.isEmpty)

        identity.set(FakeIdentity.first)
        h.ledger.serve(midgarId: FakeIdentity.first)
        await h.store.refresh()

        #expect(h.ledger.reports == ["jws-1-active"])
        #expect(h.pendingReports.isEmpty)
    }

    @Test func aTransactionAlreadyBoundToAnotherMidgarIdIsDroppedWhenTheLedgerRefusesIt() async throws {
        let h = StoreHarness(identity: FakeIdentity(nil))
        let transaction = h.transaction(token: nil)
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        h.ledger.setReportReply(.refused(403, "account_mismatch"))
        _ = try await h.store.purchase(Products.pro)

        h.identity.set(FakeIdentity.first)
        h.ledger.serve(midgarId: FakeIdentity.first)
        await h.store.refresh()

        #expect(h.pendingReports.isEmpty)
        #expect(h.logs.lines.contains { $0.contains("refused") && $0.contains("account_mismatch") })
        #expect(await h.store.isEntitled(to: "pro"))
    }

    @Test func anUnverifiedTransactionIsRefusedAndNeverFinished() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let events = await h.store.events()
        h.storeKit.queue(.success(.unverified(h.transaction(), reason: "bad signature")))

        await #expect(throws: MidgarStoreError.unverifiedTransaction(productID: Products.pro)) {
            try await h.store.purchase(Products.pro)
        }
        await h.store.refresh()

        #expect(h.finishes.ids.isEmpty)
        #expect(h.pendingReports.isEmpty)
        #expect(h.ledger.reports.isEmpty)
        #expect(!(await h.store.isEntitled(to: "pro")))
        #expect(h.logs.lines.contains { $0.contains("unverified") })
        #expect(await h.signals.events.isEmpty)
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .refused(productID: Products.pro))
    }

    @Test func aPendingPurchaseGrantsNothingAndCancellationIsReported() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.pending)
        h.storeKit.queue(.userCancelled)

        #expect(try await h.store.purchase(Products.pro) == .pending)
        #expect(try await h.store.purchase(Products.pro) == .cancelled)
        #expect(h.finishes.ids.isEmpty)
        #expect(h.pendingReports.isEmpty)
    }

    @Test func aProductTheStoreDoesNotHandleIsRefusedBeforeStoreKitSeesIt() async {
        let h = StoreHarness()
        await #expect(throws: MidgarStoreError.unknownProduct(Products.credits)) {
            try await h.store.purchase(Products.credits)
        }
        #expect(h.storeKit.purchases.isEmpty)
    }

    @Test func aTransactionFromBothThePurchaseAndTheListenerIsFinishedOnce() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        _ = try await h.store.purchase(Products.pro)
        h.storeKit.emit(.verified(transaction))
        try? await Task.sleep(for: .milliseconds(100))
        await h.store.refresh()

        #expect(h.finishes.ids == [1])
        #expect(await h.signals.events.count == 1)
    }

    @Test func xcodeSignedAndFamilySharedTransactionsAreNeverReported() async throws {
        let h = StoreHarness()
        let local = h.transaction(id: 1, environment: .xcode)
        let shared = h.transaction(id: 2, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(86_400), ownership: .familyShared)
        h.storeKit.setCurrent([.verified(local), .verified(shared)])
        h.storeKit.queue(.success(.verified(local)))
        _ = try await h.store.purchase(Products.pro)
        h.storeKit.emit(.verified(shared))
        #expect(await eventually { h.finishes.ids.contains(2) })
        await h.store.refresh()

        #expect(h.ledger.reports.isEmpty)
        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro"))
    }

    @Test func aTransactionForAnotherSystemsProductIsLeftAlone() async {
        let h = StoreHarness()
        h.storeKit.emit(.verified(h.transaction(id: 9, product: Products.credits, kind: .consumable)))
        try? await Task.sleep(for: .milliseconds(150))
        await h.store.refresh()

        #expect(h.finishes.ids.isEmpty)
        #expect(h.ledger.reports.isEmpty)
        #expect(h.pendingReports.isEmpty)
    }

    @Test func aConfirmedPurchaseTakesTheSameMoneyPath() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        let events = await h.store.events()

        let result = try await h.store.purchase(Products.pro, confirmation: StoreConfirmation(anchor: NSObject()))
        await h.store.refresh()

        #expect(result == .purchased)
        #expect(h.storeKit.purchases.first?.confirmed == true)
        #expect(h.storeKit.purchases.first?.token == UUID(uuidString: FakeIdentity.first))
        #expect(h.finishes.ids == [1])
        #expect(h.ledger.reports == ["jws-1-active"])
        #expect(await h.store.isEntitled(to: "pro"))
        #expect(await h.signals.events.count == 1)
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .entitlementsChanged)
    }

    @Test func aConfirmedUnverifiedPurchaseIsRefusedLikeAPlainOne() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.success(.unverified(h.transaction(), reason: "bad")))
        await #expect(throws: MidgarStoreError.unverifiedTransaction(productID: Products.pro)) {
            try await h.store.purchase(Products.pro, confirmation: StoreConfirmation(anchor: NSObject()))
        }
        #expect(h.finishes.ids.isEmpty)
    }

    @Test func aPlainPurchaseCarriesNoConfirmation() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.userCancelled)
        _ = try await h.store.purchase(Products.pro)
        #expect(h.storeKit.purchases.first?.confirmed == false)
    }

    #if os(macOS)
    @MainActor
    @Test func theWindowVariantOnMacOSGoesThroughTheConfirmedPath() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.userCancelled)
        let result = try await h.store.purchase(Products.pro, confirmIn: NSWindow())
        #expect(result == .cancelled)
        #expect(h.storeKit.purchases.first?.confirmed == true)
    }
    #endif
}
