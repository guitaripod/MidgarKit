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

    static let shortWindowHeight: CGFloat = 800

    static func density(forHeight height: CGFloat, isAccessibilitySize: Bool) -> MidgarPaywallBarDensity {
        if isAccessibilitySize {
            return .minimal
        }
        return height < shortWindowHeight ? .links : .full
    }

    var pinsTerms: Bool { self == .full }
    var pinsActions: Bool { self != .minimal }
}

/// The part of a plan paywall that stays on screen under the scrolling content (its text stops growing at the largest regular size, as a system bar's does, so an accessibility text size leaves the content room): the offer line of the selected plan, the purchase button, and the guideline 3.1.2 footer with the auto-renew terms, Terms of Use, Privacy Policy and Restore Purchases. Its background is opaque, so nothing scrolls visibly behind the offer line or the button.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPurchaseBar: View {
    let plan: MidgarPlan?
    let density: MidgarPaywallBarDensity
    let links: MidgarPaywallLinks
    let isPurchasing: Bool
    let isRestoring: Bool
    let purchase: () -> Void
    let restore: () -> Void
    var redeem: (() -> Void)?
    var dismiss: MidgarPaywallDismissButton?
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
                redeem: redeem,
                dismiss: dismiss,
                drawsBackground: false,
                focus: focus
            )
        }
        .padding(.top, theme.spacing.m)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .modifier(MidgarPinnedSurface())
        .overlay(alignment: .top) {
            theme.separator.color.frame(height: 1 / 3)
        }
    }

    private var purchaseButton: some View {
        Button(action: purchase) {
            ZStack {
                Text(verbatim: plan?.ctaTitle ?? MidgarCommerceUIStrings.continueButton)
                    .midgarFont(.headline)
                    .modifier(MidgarOnAccentLabel())
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
        .modifier(MidgarDefaultAction())
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

/// Return buys the selected plan on a Mac, as it does in any other sheet with a default button.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarDefaultAction: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content.keyboardShortcut(.defaultAction)
        #else
        content
        #endif
    }
}

/// The label color that reads on the accent: black on a light accent, white on a dark one.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
package struct MidgarOnAccentLabel: ViewModifier {
    package init() {}

    @Environment(\.midgarTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif

    @ViewBuilder
    package func body(content: Content) -> some View {
        #if os(macOS)
        if controlActiveState == .inactive {
            content
        } else {
            content.foregroundStyle(label)
        }
        #else
        content.foregroundStyle(label)
        #endif
    }

    private var label: Color {
        Self.isLight(theme.accent.resolved(isDark: colorScheme == .dark)) ? Color.black : Color.white
    }

    /// True when the color's relative luminance is above the point where black text reads better than white.
    package static func isLight(_ color: MidgarColor.RGBA) -> Bool {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        return luminance > 0.4
    }
}
