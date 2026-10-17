import Foundation
import Testing
@testable import MidgarCommerce

@Suite struct EntitlementTests {
    private let day: TimeInterval = 86_400

    private func passEntry(expires: TimeInterval = 30 * 86_400) -> String {
        FakeLedger.entry(app: "other", entitlement: "pass", productId: "app.midgar.other.pass", kind: "subscription", expires: commerceEpoch.addingTimeInterval(expires))
    }

    @Test func theUnionHoldsTheLedgersCrossAppGrantAndStoreKitsLocalOne() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        h.storeKit.setCurrent([.verified(h.transaction())])
        await h.store.refresh()

        let entitlements = await h.store.entitlements
        #expect(entitlements.map(\.name) == ["pass", "pro"])
        #expect(entitlements.first { $0.name == "pass" }?.sources == .ledger)
        #expect(entitlements.first { $0.name == "pass" }?.app == "other")
        #expect(entitlements.first { $0.name == "pro" }?.sources == .storeKit)
    }

    @Test func aGrantBothSidesAgreeOnCarriesBothSources() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [
            FakeLedger.entry(app: "app-test", entitlement: "pro", productId: Products.pro, kind: "non_consumable")
        ])
        h.storeKit.setCurrent([.verified(h.transaction())])
        await h.store.refresh()

        let entitlements = await h.store.entitlements
        #expect(entitlements.count == 1)
        #expect(entitlements.first?.sources == [.ledger, .storeKit])
    }

    @Test func aLedgerEntryWithoutAnEntitlementNameUsesTheAppsMapThenTheProductId() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [
            FakeLedger.entry(entitlement: nil, productId: Products.pro, kind: "non_consumable"),
            FakeLedger.entry(entitlement: nil, productId: "app.midgar.unmapped", kind: "non_consumable")
        ])
        await h.store.refresh()
        #expect(await h.store.entitlements.map(\.name) == ["app.midgar.unmapped", "pro"])
    }

    @Test func aSubscriptionInGraceIsActiveUntilTheGraceEnds() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [
            FakeLedger.entry(entitlement: "pass", productId: "p", kind: "subscription", expires: commerceEpoch.addingTimeInterval(-day), grace: commerceEpoch.addingTimeInterval(2 * day), inGrace: true)
        ])
        await h.store.refresh()
        let pass = await h.store.entitlements.first
        #expect(pass?.isInGracePeriod == true)
        #expect(pass?.expirationDate == commerceEpoch.addingTimeInterval(2 * day))

        h.clock.advance(3 * day)
        #expect(await h.store.entitlements.isEmpty)
    }

    @Test func anExpiredSubscriptionStopsGrantingAtTheDeviceClock() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [passEntry(expires: day)])
        await h.store.refresh()
        #expect(await h.store.isEntitled(to: "pass"))
        h.clock.advance(day)
        #expect(!(await h.store.isEntitled(to: "pass")))
    }

    @Test func anUnreachableLedgerFallsBackToTheCacheAndStoreKitAfterARelaunch() async throws {
        let online = StoreHarness()
        online.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        await online.store.refresh()
        #expect(online.storedLedger?.entitlements.count == 1)
        await online.store.stop()

        let offline = StoreHarness(directory: online.directory)
        offline.storeKit.setCurrent([.verified(offline.transaction())])
        await offline.store.refresh()

        #expect(await offline.store.entitlements.map(\.name) == ["pass", "pro"])
    }

    @Test func aFailedRefreshKeepsTheLastGoodAnswer() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        await h.store.refresh()
        h.ledger.setEntitlementsReply(.json(503, "{}"))
        await h.store.refresh()
        #expect(await h.store.isEntitled(to: "pass"))
    }

    @Test func aSubscriptionCacheOlderThanSevenDaysIsIgnoredButANonConsumableStays() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [
            passEntry(expires: 60 * day),
            FakeLedger.entry(entitlement: "lifetime", productId: "app.midgar.other.lifetime", kind: "non_consumable")
        ])
        await h.store.refresh()
        h.ledger.setEntitlementsReply(.unreachable)

        h.clock.advance(6 * day)
        #expect(await h.store.entitlements.map(\.name) == ["lifetime", "pass"])
        h.clock.advance(2 * day)
        #expect(await h.store.entitlements.map(\.name) == ["lifetime"])
    }

    @Test func aChangedMidgarIdClearsTheCache() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        await h.store.refresh()
        #expect(h.storedLedger?.midgarId == FakeIdentity.first.lowercased())

        h.ledger.setEntitlementsReply(.unreachable)
        h.identity.set(FakeIdentity.second)
        await h.store.refresh()

        #expect(h.storedLedger == nil)
        #expect(await h.store.entitlements.isEmpty)
    }

    @Test func anUnavailableIdentityKeepsTheCacheAndSkipsTheLedger() async throws {
        let h = StoreHarness()
        h.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        await h.store.refresh()
        let queries = h.ledger.entitlementQueries.count

        h.identity.set(nil)
        await h.store.refresh()

        #expect(h.ledger.entitlementQueries.count == queries)
        #expect(await h.store.isEntitled(to: "pass"))
    }

    @Test func aSandboxInstallAsksTheLedgerForSandboxAndProductionForProduction() async throws {
        let sandbox = StoreHarness(storeKit: FakeStoreKit(environment: .sandbox))
        sandbox.ledger.serve(midgarId: FakeIdentity.first, environment: "Sandbox")
        await sandbox.store.refresh()
        #expect(Set(sandbox.ledger.entitlementQueries) == ["Sandbox"])

        let production = StoreHarness(storeKit: FakeStoreKit(environment: .production))
        production.ledger.serve(midgarId: FakeIdentity.first)
        await production.store.refresh()
        #expect(Set(production.ledger.entitlementQueries) == [nil])
    }

    @Test func aSandboxTransactionOverridesAnUnknownEnvironment() async throws {
        let h = StoreHarness(storeKit: FakeStoreKit(environment: nil))
        h.ledger.serve(midgarId: FakeIdentity.first, environment: "Sandbox")
        let transaction = h.transaction(environment: .sandbox)
        h.storeKit.queue(.success(.verified(transaction)))
        _ = try await h.store.purchase(Products.pro)
        await h.store.refresh()
        #expect(h.ledger.entitlementQueries.last == "Sandbox")
    }

    @Test func aCacheFromAnotherEnvironmentIsDiscarded() async throws {
        let production = StoreHarness()
        production.ledger.serve(midgarId: FakeIdentity.first, [passEntry()])
        await production.store.refresh()
        await production.store.stop()

        let sandbox = StoreHarness(storeKit: FakeStoreKit(environment: .sandbox), directory: production.directory)
        await sandbox.store.refresh()
        #expect(!(await sandbox.store.isEntitled(to: "pass")))
    }

    @Test func consumablesAndNonRenewingSubscriptionsNeverGrantOnTheDevice() async throws {
        let h = StoreHarness()
        h.storeKit.setCurrent([
            .verified(h.transaction(id: 1, kind: .consumable)),
            .verified(h.transaction(id: 2, kind: .nonRenewingSubscription))
        ])
        await h.store.refresh()
        #expect(await h.store.entitlements.isEmpty)
    }

    @Test func anUnverifiedCurrentEntitlementGrantsNothing() async throws {
        let h = StoreHarness()
        h.storeKit.setCurrent([.unverified(h.transaction(), reason: "bad")])
        await h.store.refresh()
        #expect(await h.store.entitlements.isEmpty)
    }
}
