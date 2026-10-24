import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct PurchaseIntentTests {
    @Test func anAppStorePurchaseRunsTheMoneyPathWithTheMidgarIdAndIsAnnouncedAsApproved() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let events = await h.store.events()
        let bought = h.transaction()
        h.storeKit.queue(.success(.verified(bought)))
        h.storeKit.setCurrent([.verified(bought)])

        h.storeKit.intend(Products.pro)

        #expect(await eventually { await h.store.isEntitled(to: "pro") })
        #expect(h.storeKit.purchases.map(\.productID) == [Products.pro])
        #expect(h.storeKit.purchases.first?.token == UUID(uuidString: FakeIdentity.first))
        #expect(await eventually { h.finishes.ids == [1] && h.ledger.reports == ["jws-1-active"] })
        var approved = false
        for await event in events where event == .purchaseApproved(productID: Products.pro) {
            approved = true
            break
        }
        #expect(approved)
    }

    @Test func anAppStorePurchaseOfAProductThisStoreDoesNotSellIsLeftAlone() async {
        let h = StoreHarness()
        h.storeKit.intend("com.example.stranger")
        h.storeKit.intend(Products.pro)

        #expect(await eventually { h.storeKit.purchases.count == 1 })
        #expect(h.storeKit.purchases.map(\.productID) == [Products.pro])
        #expect(h.logs.lines.contains { $0.contains("com.example.stranger, which this store does not sell") })
    }

    @Test func aCancelledOrPendingAppStorePurchaseGrantsAndAnnouncesNothing() async {
        let h = StoreHarness()
        let events = await h.store.events()
        h.storeKit.queue(.userCancelled)
        h.storeKit.queue(.pending)
        h.storeKit.intend(Products.pro)
        h.storeKit.intend(Products.pro)

        #expect(await eventually { h.storeKit.purchases.count == 2 })
        #expect(await eventually { h.logs.lines.contains { $0.contains("pending approval") } })
        await h.store.stop()
        var seen: [MidgarStoreEvent] = []
        for await event in events {
            seen.append(event)
        }
        #expect(!seen.contains(.purchaseApproved(productID: Products.pro)))
        #expect(!(await h.store.isEntitled(to: "pro")))
        #expect(h.finishes.ids.isEmpty)
    }

    @Test func aReadOnlyStoreNeverListensForAppStorePurchases() async {
        let h = StoreHarness(mode: .readOnly)
        h.storeKit.intend(Products.pro)
        await h.store.refresh()
        #expect(h.storeKit.purchases.isEmpty)
    }
}
