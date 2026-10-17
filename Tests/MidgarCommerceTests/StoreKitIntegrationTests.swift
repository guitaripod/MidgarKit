import Foundation
import StoreKit
import StoreKitTest
import Testing
import MidgarCore
@testable import MidgarCommerce

final class BundleToken {}

/// The real StoreKit adapter against `SKTestSession`. They need a host app (`Tests/StoreKitHost`): `SKTestSession` cannot run inside the bare `xctest` process SwiftPM uses, so the Swift package excludes this file. They share one process-wide StoreKit, so the suite runs serially. Transactions from a test session are signed by Xcode's local certificate, so the store never reports them to the ledger.
@Suite(.serialized) struct StoreKitIntegrationTests {
    private struct Live {
        let store: MidgarStore
        let session: SKTestSession
        let ledger: FakeLedger
        let signals: SignalCapture
    }

    private func makeLive(askToBuy: Bool = false) async throws -> Live {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Products", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = askToBuy
        let ledger = FakeLedger()
        ledger.serve(midgarId: FakeIdentity.first, environment: "Sandbox")
        let identity = FakeIdentity()
        let signals = SignalCapture()
        let store = MidgarStore(
            configuration: MidgarStoreConfiguration(
                appID: "app-test",
                productIDs: [Products.pro, Products.monthly],
                entitlementsByProduct: StoreHarness.entitlementMap,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent("commerce-it-" + UUID().uuidString, isDirectory: true)
            ),
            identity: identity,
            http: makeStubClient(ledger, tokenProvider: { try await identity.midgarId }),
            storeKit: LiveStoreKit(),
            clock: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            signal: { await signals.record($0, $1) },
            logger: { _ in },
            observesForeground: false
        )
        return Live(store: store, session: session, ledger: ledger, signals: signals)
    }

    @Test func productsComeFromTheConfigurationFileWithStoreKitPrices() async throws {
        let live = try await makeLive()
        let products = try await live.store.products()
        #expect(products.map(\.id) == [Products.pro, Products.monthly])
        #expect(products.first?.displayName == "Pro")
        #expect(products.first?.displayPrice.contains("4.99") == true)
        await live.store.stop()
    }

    @Test func aPurchaseCarriesTheMidgarIdAndGrantsTheNonConsumable() async throws {
        let live = try await makeLive()
        let result = try await live.store.purchase(Products.pro)

        #expect(result == .purchased)
        #expect(await live.store.isEntitled(to: "pro"))
        var token: UUID?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.productID == Products.pro {
                token = transaction.appAccountToken
            }
        }
        #expect(token == UUID(uuidString: FakeIdentity.first))
        #expect(live.session.allTransactions().count == 1)
        #expect(await live.signals.events.count == 1)
        #expect(live.ledger.reports.isEmpty)
        await live.store.stop()
    }

    @Test func aSubscriptionRenewsOnTheTimeRateAndTheRenewalIsFinishedAndGranted() async throws {
        let live = try await makeLive()
        live.session.timeRate = .oneRenewalEveryTwoSeconds
        _ = try await live.store.purchase(Products.monthly)
        let firstExpiry = await live.store.entitlements.first?.expirationDate
        #expect(firstExpiry != nil)

        #expect(await eventually { live.session.allTransactions().filter { $0.productIdentifier == Products.monthly }.count >= 2 })
        #expect(await eventually {
            guard let expiry = await live.store.entitlements.first?.expirationDate, let firstExpiry else {
                return false
            }
            return expiry > firstExpiry
        })
        #expect(await live.signals.events.count == 1)
        await live.store.stop()
    }

    @Test func aRefundRemovesTheEntitlementThroughTheUpdatesListener() async throws {
        let live = try await makeLive()
        _ = try await live.store.purchase(Products.pro)
        #expect(await live.store.isEntitled(to: "pro"))

        let transaction = try #require(live.session.allTransactions().first)
        try live.session.refundTransaction(identifier: UInt(transaction.identifier))

        #expect(await eventually { !(await live.store.isEntitled(to: "pro")) })
        await live.store.stop()
    }

    @Test func askToBuyIsPendingUntilApproved() async throws {
        let live = try await makeLive(askToBuy: true)
        let result = try await live.store.purchase(Products.pro)
        #expect(result == .pending)
        #expect(!(await live.store.isEntitled(to: "pro")))

        let pending = try #require(live.session.allTransactions().first)
        try live.session.approveAskToBuyTransaction(identifier: UInt(pending.identifier))

        #expect(await eventually { await live.store.isEntitled(to: "pro") })
        await live.store.stop()
    }

    @Test func restoreSyncsAndKeepsTheEntitlement() async throws {
        let live = try await makeLive()
        _ = try await live.store.purchase(Products.pro)
        try await live.store.restore()
        #expect(await live.store.isEntitled(to: "pro"))
        await live.store.stop()
    }
}
