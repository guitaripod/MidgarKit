import Foundation
import StoreKit
import StoreKitTest
import SwiftUI
import Testing
@testable import MidgarCommerce
import MidgarCore
import MidgarUI
@testable import MidgarCommerceUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#endif

/// The plan paywall over real StoreKit products (`Paywall.storekit`: a yearly plan with a one week free trial, a monthly plan and a lifetime product), run from the StoreKit host app. The tests are an extension of ``PaywallSnapshotTests`` so they share its serialized suite, its StoreKit session and its PNG sink (`MIDGAR_SNAPSHOT_DIR`).
extension PaywallSnapshotTests {
    static var planConfiguration: MidgarPlanPaywallConfiguration {
        MidgarPlanPaywallConfiguration(
            productIDs: [yearly, monthly, lifetime],
            links: links,
            hero: MidgarPaywallHero(
                title: "Go Pro",
                subtitle: "Everything unlocked, on every device.",
                artwork: .symbol("sparkles"),
                features: [
                    MidgarPaywallFeature(symbol: "photo.stack", title: "The full library", detail: "Every collection, with live status"),
                    MidgarPaywallFeature(symbol: "square.grid.2x2", title: "A widget for your Home Screen"),
                    MidgarPaywallFeature(symbol: "sparkles", title: "Unlimited AI facts"),
                    MidgarPaywallFeature(symbol: "person.3.fill", title: "Family Sharing included")
                ]
            ),
            accent: MidgarColor(hex: 0x2A9D8F)
        )
    }

    /// The windows each platform renders the paywall in: narrow and wide where the platform has both. The iPad also renders the sizes of an unfolded iPhone Duo (inner display landscape and portrait, and the outer display), because a window of that width is what decides two columns.
    static var planLayouts: [(name: String, size: CGSize?)] {
        #if os(macOS)
        [("sheet", CGSize(width: 520, height: 760)), ("wide", CGSize(width: 900, height: 640))]
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            [("full", nil), ("duo-inner-landscape", CGSize(width: 951, height: 669)), ("duo-inner-portrait", CGSize(width: 669, height: 951)), ("duo-outer", CGSize(width: 466, height: 678))]
        } else {
            [("full", nil), ("small", CGSize(width: 320, height: 568))]
        }
        #else
        [("full", nil)]
        #endif
    }

    @Test func thePlanPaywallRendersEveryLayoutOfThePlatform() async throws {
        let live = try await makeLive()
        for layout in Self.planLayouts {
            try await capture(
                MidgarPlanPaywall(configuration: Self.planConfiguration, store: live.store),
                name: "plan-paywall-\(layout.name)",
                size: layout.size
            )
        }
        await live.store.stop()
    }

    #if os(tvOS)
    @Test func theFocusedPlanOnTheTVLooksLiftedAndTheSelectedOneKeepsItsAccent() async throws {
        let live = try await makeLive()
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { _ in }
        await model.load()
        let plans = model.catalog.plans

        try await capture(
            VStack(spacing: 24) {
                MidgarPlanChoice(plan: plans[0], isSelected: true, focusOverride: false) {}
                MidgarPlanChoice(plan: plans[1], isSelected: false, focusOverride: true) {}
                MidgarPlanChoice(plan: plans[2], isSelected: false, focusOverride: false) {}
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.theme.background.color),
            name: "plan-focus"
        )
        await live.store.stop()
    }
    #endif

    #if os(iOS)
    @Test func thePlanPaywallScrolledToTheEndShowsTheTimelineTheComparisonAndTheLegalText() async throws {
        let live = try await makeLive()
        try await capture(
            MidgarPlanPaywall(configuration: Self.planConfiguration, store: live.store),
            name: "plan-paywall-scrolled",
            scrolledToEnd: true
        )
        await live.store.stop()
    }
    #endif

    @Test func thePlanPaywallLoadsPlansWithStoreKitPricesAndCaptions() async throws {
        let live = try await makeLive()
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { _ in }
        await model.load()

        #expect(model.phase == .ready)
        #expect(model.catalog.plans.map(\.id) == [Self.yearly, Self.monthly, Self.lifetime])
        #expect(model.catalog.plans.map(\.displayPrice) == ["$39.99", "$4.99", "$79.99"])
        #expect(model.selectedID == Self.yearly)
        let yearly = try #require(model.catalog.plan(id: Self.yearly))
        #expect(yearly.badge == "Save 33%")
        #expect(yearly.trial?.summary == "1 week free, then $39.99/year")
        #expect(yearly.ctaTitle == "Try 1 week free")
        #expect(model.catalog.lifetimeAnchor == "2 years of Yearly costs $79.98. Lifetime is $79.99 and never renews.")
        #expect(model.catalog.plan(id: Self.lifetime)?.detailLines.contains("Family Sharing included") == true)
        await live.store.stop()
    }

    @Test func selectingAPlanChangesTheOfferLineAndTheTimeline() async throws {
        let live = try await makeLive()
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { _ in }
        await model.load()

        model.select(Self.lifetime)

        #expect(model.selectedPlan?.id == Self.lifetime)
        #expect(model.selectedPlan?.trial == nil)
        #expect(model.selectedPlan?.offerLine == "One-time purchase of $79.99. No renewal.")
        await live.store.stop()
    }

    @Test func aPlanPaywallForAStoreWithoutTheProductsShowsTheUnavailableState() async throws {
        let live = try await makeLive()
        let configuration = MidgarPlanPaywallConfiguration(
            productIDs: ["app.midgar.test.unknown"],
            links: Self.links,
            hero: MidgarPaywallHero(title: "Go Pro")
        )
        let model = MidgarPlanPaywallModel(configuration: configuration, store: live.store, trialPolicy: MidgarTrialPolicy()) { _ in }
        await model.load()

        #expect(model.phase == .unavailable)
        #expect(model.selectedPlan == nil)
        try await capture(MidgarPlanPaywall(configuration: configuration, store: live.store), name: "plan-paywall-unavailable", size: Self.unavailableSize)
        await live.store.stop()
    }

    static var unavailableSize: CGSize? {
        #if os(macOS)
        CGSize(width: 520, height: 520)
        #else
        nil
        #endif
    }

    #if os(iOS)
    @Test func thePlanPaywallRendersAtAnAccessibilityTextSize() async throws {
        let live = try await makeLive()
        try await capture(
            MidgarPlanPaywall(configuration: Self.planConfiguration, store: live.store).environment(\.dynamicTypeSize, .accessibility2),
            name: "plan-paywall-accessibility"
        )
        await live.store.stop()
    }
    #endif
}

/// The purchase tests change what StoreKit says about this customer (the trial is used up), so they reset the session before and after.
extension PaywallSnapshotTests {
    /// What a StoreKit view would run: the product's purchase with the store's options, confirmed in the first scene where the platform needs one.
    @MainActor
    static var purchaseExecutor: MidgarPurchaseExecutor {
        #if os(visionOS)
        return { product, options in
            let scene = try #require(UIApplication.shared.connectedScenes.first)
            return try await product.purchase(confirmIn: scene, options: options)
        }
        #else
        return { product, options in try await product.purchase(options: options) }
        #endif
    }

    /// The entitlement checks of the purchase tests do not run on macOS: StoreKit testing there does not grant the purchase to `Transaction.currentEntitlements` (the integration tests of `MidgarStore` fail the same way), while the events and the account token still hold.
    ///
    /// StoreKit hands the new transaction to `Transaction.currentEntitlements` a moment after the purchase returns.
    static func waitForEntitlement(in store: MidgarStore) async -> Bool {
        for _ in 0..<40 {
            if await store.isEntitled(to: "pro") {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    @Test func aLifetimePurchaseFromThePlanPaywallCarriesTheAccountTokenAndUnlocksThePlan() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()
        model.select(Self.lifetime)

        await model.purchase(using: Self.purchaseExecutor)

        #expect(events == [.purchased(productID: Self.lifetime)])
        #if !os(macOS)
        #expect(await Self.waitForEntitlement(in: live.store))
        #endif
        let latest = try #require(await Transaction.latest(for: Self.lifetime))
        let transaction = try latest.payloadValue
        #expect(transaction.appAccountToken == UUID(uuidString: FakeIdentity.first))
        #expect(model.failureMessage == nil)
        live.session.resetToDefaultState()
        live.session.clearTransactions()
        await live.store.stop()
    }

    @Test func aSubscriptionPurchaseUsesUpTheTrialAndThePlanPaywallStopsOfferingIt() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()
        #expect(model.selectedPlan?.trial != nil)

        await model.purchase(using: Self.purchaseExecutor)
        for _ in 0..<20 where model.catalog.plan(id: Self.yearly)?.trial != nil {
            try await Task.sleep(for: .milliseconds(500))
        }

        #expect(events == [.purchased(productID: Self.yearly)])
        #if !os(macOS)
        #expect(await Self.waitForEntitlement(in: live.store))
        #endif
        #if os(iOS)
        #expect(model.catalog.plan(id: Self.yearly)?.trial == nil)
        #expect(model.catalog.plan(id: Self.yearly)?.ctaTitle == "Continue")
        #endif
        live.session.resetToDefaultState()
        live.session.clearTransactions()
        await live.store.stop()
    }

    @Test func aFailingPurchaseReportsAFailureAndLeavesTheCustomerFree() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()
        model.select(Self.monthly)

        await model.purchase(using: { _, _ in throw StoreKitError.networkError(URLError(.notConnectedToInternet)) })

        #expect(events == [.failed(message: MidgarCommerceUIStrings.purchaseFailed)])
        #expect(model.failureMessage == MidgarCommerceUIStrings.purchaseFailed)
        #expect(!model.isPurchasing)
        #expect(await live.store.isEntitled(to: "pro") == false)
        await live.store.stop()
    }

    @Test func aCancelledPurchaseIsSilentAndAPendingOneToldAsToast() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()

        await model.purchase(using: { _, _ in .userCancelled })
        #expect(model.toast == nil)
        await model.purchase(using: { _, _ in .pending })

        #expect(events == [.cancelled, .pending])
        #expect(model.toast != nil)
        #expect(model.failureMessage == nil)
        await live.store.stop()
    }

    @Test func restoringFromThePlanPaywallRunsTheStoreAndReportsWhatItFound() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let model = MidgarPlanPaywallModel(configuration: Self.planConfiguration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()

        await model.restore()
        model.select(Self.lifetime)
        await model.purchase(using: Self.purchaseExecutor)
        _ = await Self.waitForEntitlement(in: live.store)
        await model.restore()

        #expect(events == [.nothingToRestore, .purchased(productID: Self.lifetime), .restored])
        #expect(!model.isRestoring)
        live.session.resetToDefaultState()
        live.session.clearTransactions()
        await live.store.stop()
    }

    @Test func aCustomerWhoOwnsAnEarlierPaidVersionOutsideTheStoreRestoresInsteadOfFindingNothing() async throws {
        let live = try await makeLive()
        var events: [MidgarPaywallEvent] = []
        let configuration = MidgarPlanPaywallConfiguration(
            productIDs: [Self.yearly, Self.monthly, Self.lifetime],
            links: Self.links,
            hero: MidgarPaywallHero(title: "Go Pro"),
            ownsPurchaseOutsideStore: { true }
        )
        let model = MidgarPlanPaywallModel(configuration: configuration, store: live.store, trialPolicy: MidgarTrialPolicy()) { events.append($0) }
        await model.load()

        await model.restore()

        #expect(events == [.restored])
        await live.store.stop()
    }
}
