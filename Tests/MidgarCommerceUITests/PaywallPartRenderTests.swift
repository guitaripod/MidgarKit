#if os(macOS) || os(iOS)
import SwiftUI
import Testing
import MidgarCommerce
@testable import MidgarCommerceUI

@Suite @MainActor struct PaywallPartRenderTests {
    private var platform: String {
        #if os(macOS)
        "mac"
        #else
        "ios"
        #endif
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

    private var planCards: some View {
        VStack(spacing: 12) {
            MidgarPlanCard(title: "Yearly", price: "$39.99/year", detail: "1 week free, then $39.99/year", badge: "1 week free", isSelected: true)
            MidgarPlanCard(title: "Monthly", price: "$4.99/month", detail: "Billed monthly")
            MidgarPlanCard(title: "Lifetime", price: "$79.99", detail: "Pay once, keep it forever", isPurchased: true)
            MidgarPlanCard(title: "Quarterly with a very long name that wraps", price: "$12.99 every 3 months", badge: "Best value")
        }
        .padding(16)
    }

    private var footer: some View {
        MidgarPaywallFooter(
            planLines: [
                MidgarPlanLine(id: "y", name: "Yearly", text: "1 week free, then $39.99/year"),
                MidgarPlanLine(id: "m", name: "Monthly", text: "$4.99/month")
            ],
            showsAutoRenew: true,
            links: MidgarPaywallLinks(
                termsOfUse: URL(string: "https://example.com/terms")!,
                privacyPolicy: URL(string: "https://example.com/privacy")!
            ),
            isRestoring: false,
            restore: {}
        )
    }

    @Test func paywallPlanCardsRender() throws {
        try check("plan-cards", size: CGSize(width: 390, height: 420), planCards)
    }

    @Test func paywallPlanCardsRenderAtAnAccessibilityTextSize() throws {
        try check("plan-cards-accessibility", size: CGSize(width: 390, height: 1500), planCards.environment(\.dynamicTypeSize, .accessibility3))
    }

    @Test func paywallFooterRendersWithEveryRequiredPart() throws {
        try check("footer", size: CGSize(width: 390, height: 240), footer)
    }

    @Test func paywallFooterRendersAtAnAccessibilityTextSize() throws {
        try check("footer-accessibility", size: CGSize(width: 390, height: 1100), footer.environment(\.dynamicTypeSize, .accessibility3))
    }
}
#endif
