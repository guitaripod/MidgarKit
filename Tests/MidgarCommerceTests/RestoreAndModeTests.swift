import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct RestoreAndModeTests {
    @Test func restoreSyncsThenReReportsEveryOwnedCurrentEntitlement() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        h.storeKit.setCurrent([
            .verified(h.transaction(id: 1)),
            .verified(h.transaction(id: 2, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(86_400))),
            .verified(h.transaction(id: 3, product: Products.credits, kind: .consumable)),
            .verified(h.transaction(id: 4, ownership: .familyShared)),
            .unverified(h.transaction(id: 5), reason: "bad")
        ])

        try await h.store.restore()

        #expect(h.storeKit.syncCount == 1)
        #expect(Set(h.ledger.reports) == ["jws-1-active", "jws-2-active"])
        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro"))
        #expect(h.finishes.ids.isEmpty)
    }

    @Test func restoreKeepsReportsTheLedgerCannotTakeYet() async throws {
        let h = StoreHarness()
        h.ledger.setReportReply(.unreachable)
        h.storeKit.setCurrent([.verified(h.transaction(id: 1))])
        try await h.store.restore()
        #expect(h.pendingReports.count == 1)
    }

    @Test func aReadOnlyStoreServesTheLedgerAndTouchesNoTransaction() async throws {
        let h = StoreHarness(mode: .readOnly)
        h.ledger.serve(midgarId: FakeIdentity.first, [
            FakeLedger.entry(app: "app-test", entitlement: "pro", productId: Products.pro, kind: "non_consumable")
        ])
        h.storeKit.setCurrent([.verified(h.transaction(id: 2, product: Products.monthly, kind: .autoRenewableSubscription, expires: commerceEpoch.addingTimeInterval(86_400)))])
        h.storeKit.emit(.verified(h.transaction(id: 3)))
        try? await Task.sleep(for: .milliseconds(150))
        await h.store.refresh()

        #expect(await h.store.entitlements.map(\.name) == ["pro"])
        #expect(await h.store.entitlements.first?.sources == .ledger)
        #expect(h.finishes.ids.isEmpty)
        #expect(h.ledger.reports.isEmpty)
        await #expect(throws: MidgarStoreError.readOnly) { try await h.store.purchase(Products.pro) }
        await #expect(throws: MidgarStoreError.readOnly) { try await h.store.restore() }
        #expect(h.storeKit.purchases.isEmpty)
        #expect(h.storeKit.syncCount == 0)
    }

    @Test func productsComeFromStoreKitForTheConfiguredIds() async throws {
        let h = StoreHarness()
        let products = try await h.store.products()
        #expect(products.map(\.id) == [Products.pro, Products.monthly])
    }

    @Test func stopEndsTheEventStreams() async {
        let h = StoreHarness()
        let events = await h.store.events()
        await h.store.stop()
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test func theLedgerRequestsCarryTheBearerToken() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        h.storeKit.setCurrent([.verified(h.transaction())])
        try await h.store.restore()
        #expect(!h.ledger.authorizations.isEmpty)
        #expect(h.ledger.authorizations.allSatisfy { $0 == "Bearer \(FakeIdentity.first)" })
    }
}
