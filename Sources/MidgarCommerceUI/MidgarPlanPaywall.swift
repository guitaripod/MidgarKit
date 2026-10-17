import MidgarCommerce
import MidgarUI
import StoreKit
import SwiftUI

/// How a plan paywall shares its window between the pitch (picture, headline, benefits) and the purchase (plans, offer, button, legal).
enum MidgarPaywallArrangement: Equatable {
    /// One scrolling column, the purchase bar pinned under it.
    case single
    /// The pitch beside the purchase, each in its own column.
    case twoColumns

    /// The narrowest window that gets two columns: an iPad, an unfolded iPhone Duo, a Mac sheet, a TV. Decided by the width the paywall is given, not by the device, so a Split View or a resized window follows.
    static let twoColumnMinimumWidth: CGFloat = 700

    static func arrangement(forWidth width: CGFloat) -> MidgarPaywallArrangement {
        width >= twoColumnMinimumWidth ? .twoColumns : .single
    }
}

/// A paywall that sells subscriptions and a one-time product in one plan picker, on the plain StoreKit API instead of `SubscriptionStoreView`.
///
/// The picker marks the selected plan and states, from StoreKit prices, what the longer plans save against monthly and how many years of the yearly plan the one-time product costs. A free trial the customer may use (``MidgarTrialPolicy``) gets a timeline of today, the reminder and the first charge. The content scrolls above a pinned purchase bar with the guideline 3.1.2 footer, in two columns when the window is wide.
///
/// Every purchase goes through the ``MidgarStore``: the purchase options carry the Midgar ID as `appAccountToken` and the result goes to ``MidgarStore/complete(_:)``, so verification, the ledger report queue and the entitlements are the same as for ``MidgarStore/purchase(_:)``. Restore runs ``MidgarStore/restore()``. visionOS needs nothing extra, because the StoreKit purchase action confirms in the view's own scene.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPlanPaywall: View {
    private let configuration: MidgarPlanPaywallConfiguration
    private let store: MidgarStore
    private let trialPolicy: MidgarTrialPolicy
    private let onEvent: @MainActor (MidgarPaywallEvent) -> Void

    @Environment(\.midgarTheme) private var theme

    /// - Parameters:
    ///   - configuration: The products to sell and the hero the app shows.
    ///   - store: The app's store. Its configured products must include every product of the configuration.
    ///   - trialPolicy: Where offers and renewal prices come from. The default asks StoreKit.
    ///   - onEvent: Called on the main actor for every outcome. Close the paywall on ``MidgarPaywallEvent/isSuccess``.
    public init(
        configuration: MidgarPlanPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.store = store
        self.trialPolicy = trialPolicy
        self.onEvent = onEvent
    }

    public var body: some View {
        MidgarPlanPaywallContent(configuration: configuration, store: store, trialPolicy: trialPolicy, onEvent: onEvent)
            .midgarTheme(accented)
    }

    private var accented: MidgarTheme {
        var themed = theme
        if let accent = configuration.accent {
            themed.accent = accent
        }
        return themed
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPlanPaywallContent: View {
    @State private var model: MidgarPlanPaywallModel
    @FocusState private var focus: MidgarPaywallFocus?
    @Environment(\.midgarTheme) private var theme
    @Environment(\.purchase) private var purchaseAction
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        configuration: MidgarPlanPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void
    ) {
        _model = State(initialValue: MidgarPlanPaywallModel(configuration: configuration, store: store, trialPolicy: trialPolicy, onEvent: onEvent))
    }

    var body: some View {
        GeometryReader { proxy in
            layout(
                MidgarPaywallArrangement.arrangement(forWidth: proxy.size.width),
                height: proxy.size.height,
                density: Self.isTV ? .minimal : .density(forHeight: proxy.size.height, isAccessibilitySize: typeSize.isAccessibilitySize)
            )
        }
        .modifier(MidgarPaywallBackground())
        .tint(theme.accent.color)
        .midgarToast($model.toast)
        .midgarFailureAlert($model.failureMessage)
        .task {
            await model.load()
            focusSelectedPlan()
        }
    }

    @ViewBuilder
    private func layout(_ arrangement: MidgarPaywallArrangement, height: CGFloat, density: MidgarPaywallBarDensity) -> some View {
        switch arrangement {
        case .single:
            singleColumn(density)
        case .twoColumns:
            twoColumns(height: height, density: density)
        }
    }

    private func singleColumn(_ density: MidgarPaywallBarDensity) -> some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                MidgarPaywallPitch(hero: model.configuration.hero, isCompact: true)
                purchaseChoices(density)
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar(density) }
    }

    private func twoColumns(height: CGFloat, density: MidgarPaywallBarDensity) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.xxl) {
            ScrollView {
                VStack(spacing: theme.spacing.xl) {
                    MidgarPaywallPitch(hero: model.configuration.hero, isCompact: Self.isTV, inlinesSymbol: Self.isTV)
                    if Self.isTV {
                        timeline
                    }
                    if Self.isTV {
                        legalTail(.minimal)
                    }
                }
                .padding(.vertical, Self.isTV ? 0 : theme.spacing.xl)
                .frame(maxWidth: Self.pitchColumnWidth)
                .frame(maxWidth: .infinity, minHeight: height)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 0) {
                ScrollView {
                    purchaseChoices(density)
                        .padding(.horizontal, theme.spacing.l)
                        .padding(.vertical, theme.spacing.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
                purchaseBar(density)
            }
            .frame(width: Self.purchaseColumnWidth)
        }
        .padding(.horizontal, theme.spacing.xl)
    }

    private static var pitchColumnWidth: CGFloat {
        #if os(tvOS)
        780
        #else
        520
        #endif
    }

    private static var purchaseColumnWidth: CGFloat {
        #if os(tvOS)
        640
        #else
        400
        #endif
    }

    /// On a TV the right column is for the plans and the button, and the timeline and the legal text sit in the pitch: the 10-foot screen has no room for them under the plans, and a compact hero keeps the pitch inside the screen.
    private static var isTV: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    @ViewBuilder
    private func purchaseChoices(_ density: MidgarPaywallBarDensity) -> some View {
        VStack(spacing: theme.spacing.l) {
            switch model.phase {
            case .loading:
                ProgressView()
                    .accessibilityLabel(MidgarCommerceUIStrings.loadingPlans)
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .unavailable:
                unavailable
            case .ready:
                MidgarPlanPicker(
                    plans: model.catalog.plans,
                    selectedID: model.selectedID,
                    isEnabled: !model.isBusy,
                    select: { model.select($0) },
                    focus: $focus
                )
                .onChange(of: focus) { _, focused in
                    followFocus(focused)
                }
                if let anchor = model.catalog.lifetimeAnchor {
                    Text(verbatim: anchor)
                        .midgarFont(.footnote)
                        .foregroundStyle(theme.secondaryLabel.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !Self.isTV {
                    timeline
                }
                if !Self.isTV {
                    legalTail(density)
                }
            }
        }
    }

    /// The part of the legal footer the purchase bar does not pin, at the end of the scrolling content.
    @ViewBuilder
    private func legalTail(_ density: MidgarPaywallBarDensity) -> some View {
        let terms = !density.pinsTerms && (model.selectedPlan?.isSubscription ?? false)
        if terms || !density.pinsActions {
            MidgarPaywallFooter(
                planLines: [],
                showsAutoRenew: terms,
                showsActions: !density.pinsActions,
                links: model.configuration.links,
                isRestoring: model.isRestoring,
                restore: { Task { await model.restore() } },
                focus: $focus
            )
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if let trial = model.selectedPlan?.trial {
            MidgarTrialTimeline(steps: MidgarTrialTimelineSteps(presentation: trial, includesReminder: model.configuration.showsTrialReminder))
                .transition(.opacity)
        }
    }

    private var unavailable: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(theme.secondaryLabel.color)
                .accessibilityHidden(true)
            Text(MidgarCommerceUIStrings.plansUnavailableTitle)
                .midgarFont(.headline)
                .foregroundStyle(theme.label.color)
            Text(MidgarCommerceUIStrings.plansUnavailableDetail)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.secondaryLabel.color)
                .multilineTextAlignment(.center)
            Button(MidgarCommerceUIStrings.tryAgain) {
                Task { await model.load() }
            }
            .midgarPurchaseButtonStyle()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func purchaseBar(_ density: MidgarPaywallBarDensity) -> some View {
        MidgarPurchaseBar(
            plan: model.phase == .ready ? model.selectedPlan : nil,
            density: model.phase == .ready ? density : .full,
            links: model.configuration.links,
            isPurchasing: model.isPurchasing,
            isRestoring: model.isRestoring,
            purchase: {
                Task { await model.purchase(using: { product, options in try await purchaseAction(product, options: options) }) }
            },
            restore: { Task { await model.restore() } },
            focus: $focus
        )
    }

    /// On tvOS the plan under the remote's focus is the selected one.
    private func followFocus(_ focused: MidgarPaywallFocus?) {
        #if os(tvOS)
        if case .plan(let id) = focused {
            model.select(id)
        }
        #endif
    }

    private func focusSelectedPlan() {
        #if os(tvOS)
        if let id = model.selectedID {
            focus = .plan(id)
        }
        #endif
    }
}

/// The paywall's own background: the theme's.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarPaywallBackground: ViewModifier {
    @Environment(\.midgarTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.background.color.ignoresSafeArea())
    }
}
