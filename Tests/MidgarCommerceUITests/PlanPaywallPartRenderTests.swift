#if os(macOS) || os(iOS)
import SwiftUI
import Testing
import MidgarCommerce
@testable import MidgarCommerceUI

@Suite @MainActor struct PlanPaywallPartRenderTests {
    private struct PickerHarness: View {
        let catalog: MidgarPlanCatalog
        let selectedID: String
        @FocusState private var focus: MidgarPaywallFocus?

        var body: some View {
            VStack(spacing: 20) {
                MidgarPlanPicker(plans: catalog.plans, selectedID: selectedID, isEnabled: true, select: { _ in }, focus: $focus)
                if let anchor = catalog.lifetimeAnchor {
                    Text(verbatim: anchor).font(.footnote).multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
    }

    private struct BarHarness: View {
        let plan: MidgarPlan?
        var isPurchasing = false
        var density = MidgarPaywallBarDensity.full
        @FocusState private var focus: MidgarPaywallFocus?

        var body: some View {
            MidgarPurchaseBar(
                plan: plan,
                density: density,
                links: MidgarPaywallLinks(termsOfUse: URL(string: "https://example.com/terms")!, privacyPolicy: URL(string: "https://example.com/privacy")!),
                isPurchasing: isPurchasing,
                isRestoring: false,
                purchase: {},
                restore: {},
                focus: $focus
            )
        }
    }

    private var platform: String {
        #if os(macOS)
        "mac"
        #else
        "ios"
        #endif
    }

    private var catalog: MidgarPlanCatalog {
        PlanFixtures.catalog()
    }

    private func check<Content: View>(_ name: String, size: CGSize, _ content: Content) throws {
        let light = try renderPaywallPart(content, size: size, dark: false)
        let dark = try renderPaywallPart(content, size: size, dark: true)
        try PaywallSnapshotSink.write(light, name: "\(platform)-\(name)-light.png")
        try PaywallSnapshotSink.write(dark, name: "\(platform)-\(name)-dark.png")
        #expect(distinctColors(in: light) > 2, "\(name) light rendered blank")
        #expect(distinctColors(in: dark) > 2, "\(name) dark rendered blank")
        #expect(light != dark, "\(name) looks the same in light and dark")
    }

    @Test func thePlanPickerRendersEveryPlanWithTheSelectedOneMarked() throws {
        try check("plan-picker", size: CGSize(width: 390, height: 520), PickerHarness(catalog: catalog, selectedID: PlanFixtures.yearly))
    }

    @Test func thePlanPickerRendersAtAnAccessibilityTextSize() throws {
        try check(
            "plan-picker-accessibility",
            size: CGSize(width: 390, height: 1700),
            PickerHarness(catalog: catalog, selectedID: PlanFixtures.lifetime).environment(\.dynamicTypeSize, .accessibility3)
        )
    }

    @Test func theTrialTimelineRendersTodayTheReminderAndTheChargeDay() throws {
        try check("trial-timeline", size: CGSize(width: 390, height: 280), MidgarTrialTimeline(presentation: PlanFixtures.trial(PlanFixtures.yearly)).padding(16))
    }

    @Test func thePurchaseBarRendersTheOfferTheButtonAndEveryRequiredLegalPart() throws {
        try check("purchase-bar", size: CGSize(width: 390, height: 330), BarHarness(plan: catalog.plan(id: PlanFixtures.yearly)))
    }

    @Test func thePurchaseBarForAOneTimeProductStatesNoAutoRenewTerms() throws {
        try check("purchase-bar-lifetime", size: CGSize(width: 390, height: 260), BarHarness(plan: catalog.plan(id: PlanFixtures.lifetime)))
    }

    @Test func thePurchaseBarShowsAProgressIndicatorWhileAPurchaseRuns() throws {
        try check("purchase-bar-purchasing", size: CGSize(width: 390, height: 330), BarHarness(plan: catalog.plan(id: PlanFixtures.yearly), isPurchasing: true))
    }

    @Test func aShortWindowPinsOnlyTheLinksAndAnAccessibilityTextSizePinsNeitherTermsNorLinks() throws {
        let yearly = catalog.plan(id: PlanFixtures.yearly)
        let links = MidgarPaywallLinks(termsOfUse: URL(string: "https://example.com/terms")!, privacyPolicy: URL(string: "https://example.com/privacy")!)
        try check(
            "purchase-bar-links",
            size: CGSize(width: 320, height: 330),
            VStack(spacing: 0) {
                BarHarness(plan: yearly, density: .links)
                MidgarPaywallFooter(planLines: [], showsAutoRenew: true, showsActions: false, links: links, isRestoring: false, restore: {})
            }
        )
        try check(
            "purchase-bar-minimal",
            size: CGSize(width: 320, height: 400),
            VStack(spacing: 0) {
                BarHarness(plan: yearly, density: .minimal)
                MidgarPaywallFooter(planLines: [], showsAutoRenew: true, links: links, isRestoring: false, restore: {})
            }
        )
    }

    @Test func thePitchRendersTheHeroAndTheFeatureRows() throws {
        let hero = MidgarPaywallHero(
            title: "Go Pro",
            subtitle: "Everything unlocked, on every device.",
            artwork: .symbol("sparkles"),
            features: [
                MidgarPaywallFeature(symbol: "photo.stack", title: "Full library", detail: "Every image, with live status"),
                MidgarPaywallFeature(symbol: "sparkles", title: "Unlimited AI facts"),
                MidgarPaywallFeature(symbol: "person.3.fill", title: "Family Sharing included")
            ]
        )
        try check("pitch", size: CGSize(width: 390, height: 460), MidgarPaywallPitch(hero: hero, isCompact: true).padding(16))
    }

    @Test func thePitchRendersAPictureBehindTheSymbolOnceItHasLoaded() async throws {
        let hero = MidgarPaywallHero(
            title: "Go Pro",
            subtitle: "Everything unlocked.",
            artwork: .picture(symbol: "sparkles", load: { Image(systemName: "moon.stars.fill") }),
            features: [MidgarPaywallFeature(symbol: "sparkles", title: "Unlimited AI facts")]
        )

        try check("pitch-picture", size: CGSize(width: 390, height: 380), MidgarPaywallPitch(hero: hero, isCompact: false).padding(16))
    }

    @Test func theFooterOffersToRedeemACodeWhenTheAppAsksForIt() throws {
        let links = MidgarPaywallLinks(termsOfUse: URL(string: "https://example.com/terms")!, privacyPolicy: URL(string: "https://example.com/privacy")!)

        try check(
            "footer-redeem",
            size: CGSize(width: 390, height: 140),
            MidgarPaywallFooter(planLines: [], showsAutoRenew: true, links: links, isRestoring: false, restore: {}, redeem: {})
        )
    }

    #if os(macOS)
    @Test func theComparisonLineWrapsOntoAsManyLinesAsTheColumnNeeds() {
        let text = "2 years of Annual costs $39.98. Lifetime is $39.99 and never renews."
        let wide = NSHostingView(rootView: MidgarLifetimeAnchor(text: text).frame(width: 700))
        let narrow = NSHostingView(rootView: MidgarLifetimeAnchor(text: text).frame(width: 200))
        let veryNarrow = NSHostingView(rootView: MidgarLifetimeAnchor(text: text).frame(width: 110))

        #expect(narrow.fittingSize.height > wide.fittingSize.height * 1.8)
        #expect(veryNarrow.fittingSize.height > narrow.fittingSize.height * 1.3)
    }
    #endif
}
#endif
