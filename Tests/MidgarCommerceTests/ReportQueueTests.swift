import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct ReportQueueTests {
    @Test func aFailedReportSurvivesARelaunchAndIsSentByTheNextStore() async throws {
        let first = StoreHarness()
        first.ledger.setReportReply(.unreachable)
        let transaction = first.transaction()
        first.storeKit.queue(.success(.verified(transaction)))
        first.storeKit.setCurrent([.verified(transaction)])
        _ = try await first.store.purchase(Products.pro)
        await first.store.refresh()
        #expect(first.pendingReports.map(\.signedTransaction) == ["jws-1-active"])
        await first.store.stop()

        let ledger = FakeLedger()
        ledger.serve(midgarId: FakeIdentity.first)
        let second = StoreHarness(ledger: ledger, directory: first.directory)
        #expect(await eventually { ledger.reports == ["jws-1-active"] && second.pendingReports.isEmpty })
    }

    @Test func theBackgroundRetryResendsAfterItsDelay() async throws {
        let h = StoreHarness()
        h.ledger.setReportReply(.unreachable)
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        _ = try await h.store.purchase(Products.pro)
        await h.store.refresh()
        #expect(await eventually { !h.sleeper.requested.isEmpty })
        #expect(h.sleeper.requested.first == .seconds(5))
        #expect(h.pendingReports.count == 1)

        h.ledger.setReportReply(.accepted)
        h.sleeper.releaseAll()

        #expect(await eventually { h.pendingReports.isEmpty })
        #expect(h.ledger.reports.contains("jws-1-active"))
    }

    @Test(arguments: [StubReply.json(503, "{}"), StubReply.refused(401, "invalid_token"), StubReply.refused(404, "not_found"), StubReply.refused(429, "rate_limited"), StubReply.refused(400, "other")])
    func aTransientOrUnknownFailureKeepsTheReport(reply: StubReply) async throws {
        let h = StoreHarness()
        h.ledger.setReportReply(reply)
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        _ = try await h.store.purchase(Products.pro)
        await h.store.refresh()

        #expect(h.pendingReports.count == 1)
    }

    @Test(arguments: [("account_mismatch", 403), ("bundle_mismatch", 400), ("unverifiable_payload", 400), ("invalid_request", 400)])
    func aPermanentRefusalDropsTheReport(code: String, status: Int) async throws {
        let h = StoreHarness()
        h.ledger.setReportReply(.refused(status, code))
        let transaction = h.transaction()
        h.storeKit.queue(.success(.verified(transaction)))
        h.storeKit.setCurrent([.verified(transaction)])
        _ = try await h.store.purchase(Products.pro)
        await h.store.refresh()

        #expect(h.pendingReports.isEmpty)
        #expect(await h.store.isEntitled(to: "pro"))
    }

    @Test func aRefundReplacesTheQueuedVersionOfTheSameTransaction() async throws {
        let h = StoreHarness()
        h.ledger.setReportReply(.unreachable)
        let original = h.transaction()
        h.storeKit.setCurrent([.verified(original)])
        h.storeKit.queue(.success(.verified(original)))
        _ = try await h.store.purchase(Products.pro)
        h.storeKit.setCurrent([])
        h.storeKit.emit(.verified(h.transaction(revoked: commerceEpoch)))
        #expect(await eventually { h.pendingReports.map(\.signedTransaction) == ["jws-1-revoked"] })
    }
}
