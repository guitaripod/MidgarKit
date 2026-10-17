import Foundation
import Testing
import MidgarCore
@testable import MidgarCommerce

@Suite struct CreditsReceiptTests {
    @Test func purchaseReceiptForCreditsCarriesTheVerifiedTransaction() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first)
        let transaction = h.transaction(id: 77)
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])

        let result = try await h.store.purchaseReceipt(Products.pro)

        let expected = MidgarPurchaseReceipt(
            productID: Products.pro,
            transactionID: "77",
            signedTransaction: "jws-77-active",
            environment: "production"
        )
        #expect(result == .purchased(expected))
        #expect(h.storeKit.purchases.first?.token == UUID(uuidString: FakeIdentity.first))
        #expect(h.finishes.ids == [77])
        #expect(h.pendingReports.count <= 1)
    }

    @Test func purchaseReceiptForCreditsReportsCancelledAndPendingWithoutAReceipt() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.userCancelled)
        h.storeKit.queue(.pending)

        #expect(try await h.store.purchaseReceipt(Products.pro) == .cancelled)
        #expect(try await h.store.purchaseReceipt(Products.pro) == .pending)
        #expect(h.finishes.ids.isEmpty)
    }

    @Test func purchaseReceiptForCreditsRefusesProductsTheStoreDoesNotHandleAndReadOnlyStores() async throws {
        let h = StoreHarness()
        await #expect(throws: MidgarStoreError.unknownProduct("other")) {
            try await h.store.purchaseReceipt("other")
        }
        let readOnly = StoreHarness(mode: .readOnly)
        await #expect(throws: MidgarStoreError.readOnly) {
            try await readOnly.store.purchaseReceipt(Products.pro)
        }
        #expect(h.storeKit.purchases.isEmpty)
    }

    @Test func purchaseReceiptForCreditsThrowsForAnUnverifiedTransactionAndFinishesNothing() async throws {
        let h = StoreHarness()
        h.storeKit.queue(.success(.unverified(h.transaction(id: 5), reason: "bad signature")))

        await #expect(throws: MidgarStoreError.unverifiedTransaction(productID: Products.pro)) {
            try await h.store.purchaseReceipt(Products.pro)
        }
        #expect(h.finishes.ids.isEmpty)
    }
}
