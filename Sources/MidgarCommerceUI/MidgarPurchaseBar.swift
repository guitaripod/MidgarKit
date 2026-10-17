import MidgarUI
import SwiftUI

/// How much of the legal footer stays pinned under the content. A short window or a large text size pins less, and the rest moves to the end of the scrolling content, so the content keeps room to be read.
enum MidgarPaywallBarDensity: Equatable {
    /// The auto-renew terms and the links stay pinned.
    case full
    /// Only the links stay pinned. The terms follow the plans.
    case links
    /// Only the offer and the button stay pinned. The terms and the links follow the plans.
    case minimal

    static let shortWindowHeight: CGFloat = 640

    static func density(forHeight height: CGFloat, isAccessibilitySize: Bool) -> MidgarPaywallBarDensity {
        if isAccessibilitySize {
            return .minimal
        }
        return height < shortWindowHeight ? .links : .full
    }

    var pinsTerms: Bool { self == .full }
    var pinsActions: Bool { self != .minimal }
}

/// The part of a plan paywall that stays on screen under the scrolling content: the offer line of the selected plan, the purchase button, and the guideline 3.1.2 footer with the auto-renew terms, Terms of Use, Privacy Policy and Restore Purchases. Its background is opaque, so nothing scrolls visibly behind the offer line or the button.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPurchaseBar: View {
    let plan: MidgarPlan?
    let density: MidgarPaywallBarDensity
    let links: MidgarPaywallLinks
    let isPurchasing: Bool
    let isRestoring: Bool
    let purchase: () -> Void
    let restore: () -> Void
    let focus: FocusState<MidgarPaywallFocus?>.Binding

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            if let plan {
                Text(verbatim: plan.offerLine)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.label.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, theme.spacing.l)
            }
            if plan != nil {
                purchaseButton
                    .padding(.horizontal, theme.spacing.l)
            }
            MidgarPaywallFooter(
                planLines: [],
                showsAutoRenew: density.pinsTerms && (plan?.isSubscription ?? false),
                showsActions: density.pinsActions || plan == nil,
                links: links,
                isRestoring: isRestoring,
                restore: restore,
                focus: focus
            )
        }
        .padding(.top, theme.spacing.m)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .modifier(MidgarPurchaseBarBackground())
        .overlay(alignment: .top) {
            theme.separator.color.frame(height: 1 / 3)
        }
    }

    private var purchaseButton: some View {
        Button(action: purchase) {
            ZStack {
                Text(verbatim: plan?.ctaTitle ?? MidgarCommerceUIStrings.continueButton)
                    .midgarFont(.headline)
                    .opacity(isPurchasing ? 0 : 1)
                if isPurchasing {
                    ProgressView()
                        .accessibilityLabel(MidgarCommerceUIStrings.purchasing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
            .padding(.vertical, Self.buttonPadding)
        }
        .midgarPurchaseButtonStyle()
        .tint(theme.accent.color)
        .disabled(plan == nil || isPurchasing || isRestoring)
        .focused(focus, equals: .purchase)
    }

    private static var buttonHeight: CGFloat {
        #if os(tvOS)
        64
        #elseif os(visionOS)
        44
        #else
        24
        #endif
    }

    private static var buttonPadding: CGFloat {
        #if os(tvOS) || os(visionOS)
        0
        #else
        2
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension View {
    /// The filled purchase button: Liquid Glass in the accent on iOS, macOS and tvOS 26 and later, the solid bordered-prominent style before that and on visionOS, whose glass is the window's own.
    @ViewBuilder
    func midgarPurchaseButtonStyle() -> some View {
        #if os(visionOS)
        buttonStyle(.borderedProminent).controlSize(.large)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            buttonStyle(.glassProminent).controlSize(.large)
        } else {
            buttonStyle(.borderedProminent).controlSize(.large)
        }
        #endif
    }
}

/// An opaque backdrop for the bar, so nothing scrolls visibly behind it: the theme's background.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarPurchaseBarBackground: ViewModifier {
    @Environment(\.midgarTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.background.color.ignoresSafeArea(edges: .bottom))
    }
}
