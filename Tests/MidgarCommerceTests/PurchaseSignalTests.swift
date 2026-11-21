import Foundation
import Testing
@testable import MidgarCommerce

/// `paywall.purchase` counts a purchase this install made, and nothing else the updates listener delivers.
@Suite struct PurchaseSignalTests {
    private let day: TimeInterval = 86_400

    private func arrive(_ transaction: StoreTransaction, in h: StoreHarness) async {
        h.storeKit.setCurrent([.verified(transaction)])
        h.storeKit.emit(.verified(transaction))
        #expect(await eventually { h.finishes.ids.contains(transaction.id) })
        await h.store.refresh()
    }

    @Test func aPurchaseMadeOnAnotherDeviceGrantsTheEntitlementAndIsNotCounted() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)

        await arrive(h.transaction(id: 40), in: h)

        #expect(await h.store.isEntitled(to: "pro"))
        #expect(h.ledger.reports == ["jws-40-active"])
        #expect(await h.signals.events.isEmpty)
    }

    @Test func anApprovedAskToBuyStartedHereCountsOnce() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.pending)
        #expect(try await h.store.purchase(Products.pro) == .pending)
        #expect(await h.signals.events.isEmpty)

        await arrive(h.transaction(id: 41), in: h)
        #expect(await h.signals.events.map(\.name) == ["paywall.purchase"])

        await arrive(h.transaction(id: 42), in: h)
        #expect(await h.signals.events.count == 1)
    }

    @Test func anApprovalIsWaitedForAcrossARelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("commerce-" + UUID().uuidString, isDirectory: true)
        let first = StoreHarness(directory: directory)
        first.storeKit.queue(.pending)
        #expect(try await first.store.purchase(Products.pro) == .pending)

        let relaunched = StoreHarness(directory: directory)
        await arrive(relaunched.transaction(id: 43), in: relaunched)

        #expect(await relaunched.signals.events.count == 1)
        #expect(CommerceStorage(directory: directory, appID: "app-test").load().awaited == nil)
    }

    @Test func anApprovalForAnotherProductIsNotTheOneWaitedFor() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.pending)
        #expect(try await h.store.purchase(Products.pro) == .pending)

        await arrive(h.transaction(id: 44, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(30 * day)), in: h)

        #expect(await h.signals.events.isEmpty)
    }

    @Test func anApprovalThatComesAfterAMonthIsNoLongerWaitedFor() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.pending)
        #expect(try await h.store.purchase(Products.pro) == .pending)
        h.clock.advance(MidgarStore.approvalLifetime + 1)

        await arrive(h.transaction(id: 45), in: h)

        #expect(await h.signals.events.isEmpty)
    }

    @Test func aPendingPurchaseFromAStoreKitViewWaitsForAnyProduct() async throws {
        let h = StoreHarness()
        #expect(try await h.store.complete(StorePurchaseOutcome.pending) == .pending)

        await arrive(h.transaction(id: 46, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(30 * day)), in: h)

        #expect(await h.signals.events.count == 1)
    }

    @Test func aRedemptionIsWaitedForOnlyBriefly() async throws {
        let h = StoreHarness()
        await h.store.expectPurchase(of: nil, for: MidgarStore.redemptionLifetime)
        h.clock.advance(MidgarStore.redemptionLifetime + 1)

        await arrive(h.transaction(id: 47), in: h)

        #expect(await h.signals.events.isEmpty)
    }

    @Test func aPurchaseThatSucceedsHereAfterAPendingOneLeavesNothingWaiting() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.pending)
        #expect(try await h.store.purchase(Products.pro) == .pending)
        let bought = h.transaction(id: 48)
        h.storeKit.setCurrent([.verified(bought)])
        h.storeKit.queue(.success(.verified(bought)))
        #expect(try await h.store.purchase(Products.pro) == .purchased)
        #expect(await h.signals.events.count == 1)

        await arrive(h.transaction(id: 49), in: h)

        #expect(await h.signals.events.count == 1)
    }

    @Test func aRenewalOrARefundIsNeverCountedEvenWhileAPurchaseIsWaitedFor() async throws {
        let h = StoreHarness()
        await h.store.expectPurchase(of: nil, for: MidgarStore.approvalLifetime)

        await arrive(h.transaction(id: 51, original: 50, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(30 * day)), in: h)
        await arrive(h.transaction(id: 52, revoked: commerceEpoch), in: h)

        #expect(await h.signals.events.isEmpty)
    }
}
