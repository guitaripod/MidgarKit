import Foundation
import MidgarCore
import Testing
@testable import MidgarCommerce

/// What the store tells signals: whether the install pays, a purchase made here, and a renewal turned off.
@Suite struct StoreContextTests {
    private let day: TimeInterval = 86_400

    private func tiers(_ h: StoreHarness) async -> [MidgarSignal.Tier] {
        await h.notes.notes.compactMap { note in
            if case .tier(let tier) = note { return tier }
            return nil
        }
    }

    private func renewalsOff(_ h: StoreHarness) async -> [Date] {
        await h.notes.notes.compactMap { note in
            if case .renewalOff(let startedAt) = note { return startedAt }
            return nil
        }
    }

    @Test func anInstallIsFreeUntilItBuysAndPaidAfter() async throws {
        let h = StoreHarness()
        await h.store.refresh()
        #expect(await tiers(h).last == .free)

        let bought = h.transaction(id: 50)
        h.storeKit.queue(.success(.verified(bought)))
        h.storeKit.setCurrent([.verified(bought)])
        _ = try await h.store.purchase(Products.pro)
        await h.store.refresh()

        #expect(await tiers(h).last == .paid)
        #expect(await h.notes.notes.filter { $0 == .purchased }.count == 1)
    }

    @Test func aPurchaseThatArrivedFromElsewhereTellsNoStory() async {
        let h = StoreHarness()
        let arrived = h.transaction(id: 51)
        h.storeKit.setCurrent([.verified(arrived)])
        h.storeKit.emit(.verified(arrived))
        #expect(await eventually { h.finishes.ids.contains(51) })
        await h.store.refresh()

        #expect(await tiers(h).last == .paid)
        #expect(await h.notes.notes.contains(.purchased) == false)
    }

    @Test func aFreeIntroductoryPeriodIsATrialUntilItIsPaidFor() async {
        let h = StoreHarness()
        var trial = h.transaction(id: 52, product: Products.monthly, kind: .autoRenewableSubscription, expires: h.clock.now.addingTimeInterval(7 * day))
        trial.isTrial = true
        h.storeKit.setCurrent([.verified(trial)])
        await h.store.refresh()
        #expect(await tiers(h).last == .trial)

        let renewed = h.transaction(id: 53, original: 52, product: Products.monthly, kind: .autoRenewableSubscription, expires: h.clock.now.addingTimeInterval(37 * day))
        h.storeKit.setCurrent([.verified(renewed)])
        await h.store.refresh()
        #expect(await tiers(h).last == .paid)
    }

    @Test func anInstallThatHeldAnEntitlementIsLapsedOnceItEndsEvenAfterARelaunch() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("commerce-" + UUID().uuidString, isDirectory: true)
        let h = StoreHarness(directory: directory)
        let subscription = h.transaction(id: 54, product: Products.monthly, kind: .autoRenewableSubscription, expires: h.clock.now.addingTimeInterval(day))
        h.storeKit.setCurrent([.verified(subscription)])
        await h.store.refresh()
        #expect(await tiers(h).last == .paid)

        let relaunched = StoreHarness(directory: directory)
        await relaunched.store.refresh()
        #expect(await tiers(relaunched).last == .lapsed)
    }

    @Test func aRenewalTurnedOffIsToldOnceUntilItChangesBack() async {
        let h = StoreHarness()
        let started = h.clock.now.addingTimeInterval(-100 * day)
        func renewal(_ willAutoRenew: Bool) -> StoreRenewal {
            StoreRenewal(originalID: 60, productID: Products.monthly, willAutoRenew: willAutoRenew, startedAt: started)
        }

        h.storeKit.setRenewals([renewal(true)])
        await h.store.refresh()
        #expect(await renewalsOff(h).isEmpty)

        h.storeKit.setRenewals([renewal(false)])
        await h.store.refresh()
        await h.store.refresh()
        #expect(await renewalsOff(h) == [started])

        h.storeKit.setRenewals([renewal(true)])
        await h.store.refresh()
        h.storeKit.setRenewals([renewal(false)])
        await h.store.refresh()
        #expect(await renewalsOff(h) == [started, started])
    }

    @Test func aTurnedOffRenewalIsRememberedAcrossARelaunchAndForgottenWhenTheSubscriptionEnds() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("commerce-" + UUID().uuidString, isDirectory: true)
        let off = StoreRenewal(originalID: 61, productID: Products.monthly, willAutoRenew: false, startedAt: commerceEpoch)
        let first = StoreHarness(directory: directory)
        first.storeKit.setRenewals([off])
        await first.store.refresh()
        #expect(await renewalsOff(first).count == 1)
        #expect(CommerceStorage(directory: directory, appID: "app-test").load().renewalsOff == ["61"])

        let relaunched = StoreHarness(directory: directory)
        relaunched.storeKit.setRenewals([off])
        await relaunched.store.refresh()
        #expect(await renewalsOff(relaunched).isEmpty)

        relaunched.storeKit.setRenewals([])
        await relaunched.store.refresh()
        #expect(CommerceStorage(directory: directory, appID: "app-test").load().renewalsOff == nil)
    }

    @Test func aRenewalOfAProductTheStoreDoesNotHandleIsLeftAlone() async {
        let h = StoreHarness()
        h.storeKit.setRenewals([StoreRenewal(originalID: 62, productID: "com.other.app.pro", willAutoRenew: false, startedAt: commerceEpoch)])
        await h.store.refresh()
        #expect(await renewalsOff(h).isEmpty)
    }
}
