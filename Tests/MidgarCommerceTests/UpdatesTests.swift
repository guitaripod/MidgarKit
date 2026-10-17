import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct UpdatesTests {
    private let day: TimeInterval = 86_400

    @Test func aRenewalArrivingThroughUpdatesExtendsTheEntitlementWithoutAnotherPurchaseSignal() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let first = h.transaction(id: 10, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(30 * day))
        h.storeKit.setCurrent([.verified(first)])
        h.storeKit.emit(.verified(first))
        #expect(await eventually { await h.store.isEntitled(to: "pro") })

        let renewal = h.transaction(id: 11, original: 10, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(60 * day))
        h.storeKit.setCurrent([.verified(renewal)])
        h.storeKit.emit(.verified(renewal))
        #expect(await eventually { h.finishes.ids.contains(11) && h.ledger.reports.contains("jws-11-active") })
        await h.store.refresh()

        let pro = await h.store.entitlements.first { $0.name == "pro" }
        #expect(pro?.expirationDate == commerceEpoch.addingTimeInterval(60 * day))
        #expect(pro?.kind == .subscription)
        #expect(h.finishes.ids == [10, 11])
        #expect(await h.signals.events.count == 1)
    }

    @Test func aRefundRemovesTheEntitlementAndIsReportedToTheLedger() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let bought = h.transaction()
        h.storeKit.setCurrent([.verified(bought)])
        h.storeKit.emit(.verified(bought))
        #expect(await eventually { await h.store.isEntitled(to: "pro") })

        h.storeKit.setCurrent([])
        h.ledger.serve(midgarId: FakeIdentity.first)
        h.storeKit.emit(.verified(h.transaction(revoked: commerceEpoch)))

        #expect(await eventually { !(await h.store.isEntitled(to: "pro")) })
        #expect(await eventually { h.ledger.reports.contains("jws-1-revoked") })
    }

    @Test func aRevokedTransactionStillListedByStoreKitGrantsNothing() async throws {
        let h = StoreHarness()
        let revoked = h.transaction(revoked: commerceEpoch)
        h.storeKit.setCurrent([.verified(revoked)])
        await h.store.refresh()
        #expect(!(await h.store.isEntitled(to: "pro")))
    }

    @Test func aFamilySharingRevocationRemovesTheSharedEntitlementWithoutReporting() async throws {
        let h = StoreHarness()
        let shared = h.transaction(id: 5, ownership: .familyShared)
        h.storeKit.setCurrent([.verified(shared)])
        h.storeKit.emit(.verified(shared))
        #expect(await eventually { await h.store.entitlements.first?.ownership == .familyShared })

        h.storeKit.setCurrent([])
        h.storeKit.emit(.verified(h.transaction(id: 5, revoked: commerceEpoch, ownership: .familyShared)))

        #expect(await eventually { !(await h.store.isEntitled(to: "pro")) })
        await h.store.refresh()
        #expect(h.ledger.reports.isEmpty)
        #expect(h.pendingReports.isEmpty)
    }

    @Test func aFamilySharingRevocationThatOnlyDisappearsFromCurrentEntitlementsAlsoRemovesIt() async throws {
        let h = StoreHarness()
        h.storeKit.setCurrent([.verified(h.transaction(id: 5, ownership: .familyShared))])
        await h.store.refresh()
        #expect(await h.store.isEntitled(to: "pro"))

        h.storeKit.setCurrent([])
        await h.store.refresh()
        #expect(!(await h.store.isEntitled(to: "pro")))
    }

    @Test func askToBuyIsPendingUntilTheApprovalArrivesThroughUpdates() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let events = await h.store.events()
        h.storeKit.queue(.pending)

        #expect(try await h.store.purchase(Products.pro) == .pending)
        #expect(!(await h.store.isEntitled(to: "pro")))
        #expect(h.finishes.ids.isEmpty)

        let approved = h.transaction()
        h.storeKit.setCurrent([.verified(approved)])
        h.storeKit.emit(.verified(approved))

        #expect(await eventually { await h.store.isEntitled(to: "pro") })
        #expect(await eventually { h.ledger.reports == ["jws-1-active"] })
        #expect(h.finishes.ids == [1])
        var seen: [MidgarStoreEvent] = []
        for await event in events {
            seen.append(event)
            if seen.contains(.purchaseApproved(productID: Products.pro)) && seen.contains(.entitlementsChanged) {
                break
            }
        }
        #expect(seen.contains(.purchaseApproved(productID: Products.pro)))
        #expect(await h.signals.events.count == 1)
    }

    @Test func anUnverifiedUpdateIsRefusedNotFinishedAndNotGranted() async throws {
        let h = StoreHarness()
        let events = await h.store.events()
        h.storeKit.emit(.unverified(h.transaction(), reason: "bad"))
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .refused(productID: Products.pro))
        #expect(h.finishes.ids.isEmpty)
        #expect(h.pendingReports.isEmpty)
        #expect(!(await h.store.isEntitled(to: "pro")))
    }

    @Test func aRedeemedOfferCodeArrivesAsANewPurchaseThroughTheSamePath() async throws {
        let h = StoreHarness()
        let redeemed = h.transaction(id: 20, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(7 * day))
        h.storeKit.setCurrent([.verified(redeemed)])
        h.storeKit.emit(.verified(redeemed))
        #expect(await eventually { await h.store.isEntitled(to: "pro") && h.finishes.ids == [20] })
        #expect(await eventually { await h.signals.events.count == 1 })
    }
}
