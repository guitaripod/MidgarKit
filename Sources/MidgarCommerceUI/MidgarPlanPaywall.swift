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
    /// A horizontal fold divides the window: the pitch in the region above it, the purchase on the base below.
    case divided

    /// The narrowest window that gets two columns, and only when it is wider than tall: an iPad or a Mac window in landscape, an unfolded iPhone Duo, a TV. A tall window of the same width (an iPad in portrait, a Mac sheet) has room for one comfortable column, not two cramped ones. Decided by the size the paywall is given, not by the device, so a Split View or a resized window follows.
    static let twoColumnMinimumWidth: CGFloat = 700

    /// An accessibility text size keeps one column (a TV has no text size to choose, and its columns are drawn for the 10-foot screen): the plans and their captions would not fit the width of a second one without breaking words.
    static func arrangement(forWidth width: CGFloat, height: CGFloat, fold: MidgarFoldDivision? = nil, isAccessibilitySize: Bool = false) -> MidgarPaywallArrangement {
        if let fold, fold.axis == .rows, fold.isActive {
            return .divided
        }
        return width >= twoColumnMinimumWidth && width > height && !isAccessibilitySize ? .twoColumns : .single
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
    private let dismiss: MidgarPaywallDismissButton?
    private let onEvent: @MainActor (MidgarPaywallEvent) -> Void

    @Environment(\.midgarTheme) private var theme

    /// - Parameters:
    ///   - configuration: The products to sell and the hero the app shows.
    ///   - store: The app's store. Its configured products must include every product of the configuration.
    ///   - trialPolicy: Where offers and renewal prices come from. The default asks StoreKit.
    ///   - dismiss: A button that leaves the paywall, drawn with the footer links. Pass one where the platform has no close control of its own, such as tvOS.
    ///   - onEvent: Called on the main actor for every outcome. Close the paywall on ``MidgarPaywallEvent/isSuccess``.
    public init(
        configuration: MidgarPlanPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        dismiss: MidgarPaywallDismissButton? = nil,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.store = store
        self.trialPolicy = trialPolicy
        self.dismiss = dismiss
        self.onEvent = onEvent
    }

    public var body: some View {
        MidgarPlanPaywallContent(configuration: configuration, store: store, trialPolicy: trialPolicy, dismiss: dismiss, onEvent: onEvent)
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
    @State private var fold: MidgarFoldDivision?
    @FocusState private var focus: MidgarPaywallFocus?
    @Environment(\.midgarTheme) private var theme
    @Environment(\.purchase) private var purchaseAction
    @Environment(\.dynamicTypeSize) private var typeSize

    private let dismiss: MidgarPaywallDismissButton?

    init(
        configuration: MidgarPlanPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy,
        dismiss: MidgarPaywallDismissButton? = nil,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void
    ) {
        self.dismiss = dismiss
        _model = State(initialValue: MidgarPlanPaywallModel(configuration: configuration, store: store, trialPolicy: trialPolicy, onEvent: onEvent))
    }

    var body: some View {
        GeometryReader { proxy in
            layout(
                MidgarPaywallArrangement.arrangement(forWidth: proxy.size.width, height: proxy.size.height, fold: fold, isAccessibilitySize: typeSize.isAccessibilitySize && !Self.isTV),
                size: proxy.size,
                density: Self.isTV ? .minimal : .density(forHeight: proxy.size.height, isAccessibilitySize: typeSize.isAccessibilitySize)
            )
            .environment(\.midgarPaywallBackdrop, MidgarPaywallBackdrop(colors: model.configuration.backdrop, size: proxy.size, insets: proxy.safeAreaInsets))
        }
        .midgarFold { fold = $0 }
        .coordinateSpace(name: MidgarPaywallSpace.name)
        .modifier(MidgarPaywallBackground(colors: model.configuration.backdrop))
        .modifier(MidgarOutcomeFeedback(successes: model.successCount, failures: model.failureCount))
        .modifier(MidgarOfferCodeSheet(model: model))
        .tint(theme.accent.color)
        .midgarToast($model.toast)
        .midgarFailureAlert($model.failureMessage)
        .task {
            await model.load()
            focusSelectedPlan()
        }
    }

    @ViewBuilder
    private func layout(_ arrangement: MidgarPaywallArrangement, size: CGSize, density: MidgarPaywallBarDensity) -> some View {
        switch arrangement {
        case .single:
            singleColumn(density)
        case .twoColumns:
            twoColumns(height: size.height, fold: fold?.axis == .columns ? fold : nil, density: density)
        case .divided:
            if let fold {
                divided(fold, height: size.height, isAccessibilitySize: typeSize.isAccessibilitySize)
            }
        }
    }

    private func singleColumn(_ density: MidgarPaywallBarDensity) -> some View {
        VStack(spacing: 0) {
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
            .mask(MidgarScrollFade())
            purchaseBar(density)
        }
    }

    private func twoColumns(height: CGFloat, fold: MidgarFoldDivision?, density: MidgarPaywallBarDensity) -> some View {
        HStack(alignment: .top, spacing: fold == nil ? theme.spacing.xxl : 0) {
            pitchColumn(height: height)
                .frame(width: fold?.frame.minX)
            if let fold {
                Color.clear.frame(width: fold.frame.width)
            }
            purchaseColumn(density, isFoldAligned: fold != nil)
        }
        .padding(.horizontal, fold == nil ? theme.spacing.xl : 0)
    }

    private func pitchColumn(height: CGFloat) -> some View {
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
            .padding(.horizontal, theme.spacing.l)
            .frame(maxWidth: Self.pitchColumnWidth)
            .frame(maxWidth: .infinity, minHeight: Self.isTV ? height : nil, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .mask(MidgarScrollFade())
    }

    @ViewBuilder
    private func purchaseColumn(_ density: MidgarPaywallBarDensity, isFoldAligned: Bool) -> some View {
        let column = VStack(spacing: 0) {
            ScrollView {
                purchaseChoices(density)
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.xl)
                    .frame(maxWidth: Self.purchaseColumnWidth)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .mask(MidgarScrollFade())
            purchaseBar(density)
        }
        if isFoldAligned {
            column.frame(maxWidth: .infinity)
        } else {
            column.frame(width: Self.purchaseColumnWidth)
        }
    }

    /// A horizontal fold gives the pitch the region above it and the purchase the base below, so the plans and the button stay on the stable half and the fold never cuts a row. The pitch region is short, so it scrolls and fades out at the fold instead of cutting a row in half.
    private func divided(_ fold: MidgarFoldDivision, height: CGFloat, isAccessibilitySize: Bool) -> some View {
        let density = MidgarPaywallBarDensity.density(forHeight: height - fold.frame.maxY, isAccessibilitySize: isAccessibilitySize)
        return VStack(spacing: 0) {
            ScrollView {
                MidgarPaywallPitch(hero: model.configuration.hero, isCompact: true)
                    .padding(.horizontal, theme.spacing.l)
                    .padding(.vertical, theme.spacing.l)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: fold.frame.minY)
            .mask(MidgarFoldFade())
            Color.clear.frame(height: fold.frame.height)
            purchaseColumn(density, isFoldAligned: true)
        }
    }

    private static var pitchColumnWidth: CGFloat {
        #if os(tvOS)
        860
        #else
        520
        #endif
    }

    private static var purchaseColumnWidth: CGFloat {
        #if os(tvOS)
        760
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
                    MidgarLifetimeAnchor(text: anchor)
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
                redeem: redeemAction,
                dismiss: dismiss,
                drawsBackground: false,
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
            redeem: redeemAction,
            dismiss: dismiss,
            focus: $focus
        )
    }

    private var redeemAction: (() -> Void)? {
        guard model.configuration.offersCodeRedemption, Self.supportsOfferCodes else {
            return nil
        }
        return { model.redeemCode() }
    }

    private static var supportsOfferCodes: Bool {
        #if os(tvOS)
        false
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            true
        } else {
            false
        }
        #else
        true
        #endif
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

/// The line that compares the one-time product with years of the yearly plan. It wraps onto as many lines as the column needs, and never truncates.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarLifetimeAnchor: View {
    let text: String

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        Text(verbatim: text)
            .midgarFont(.footnote)
            .foregroundStyle(theme.secondaryLabel.color)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// The last stretch of a scrolling area fades out, which says there is more to scroll without a line cut in half at the edge. The content's own bottom padding is taller than the fade, so the end of the content is never faded.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarScrollFade: View {
    private static let height: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height)
        }
    }
}

/// The last stretch of the pitch region above a fold fades out, which says there is more to scroll without a row cut in half.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarFoldFade: View {
    private static let height: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height)
        }
    }
}

/// A tick of haptic feedback when a purchase or a restore succeeds and a different one when it fails, where the OS has it.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarOutcomeFeedback: ViewModifier {
    let successes: Int
    let failures: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            content
                .sensoryFeedback(.success, trigger: successes)
                .sensoryFeedback(.error, trigger: failures)
        } else {
            content
        }
        #else
        content
            .sensoryFeedback(.success, trigger: successes)
            .sensoryFeedback(.error, trigger: failures)
        #endif
    }
}

/// The App Store's offer code sheet, where the platform has it.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarOfferCodeSheet: ViewModifier {
    @Bindable var model: MidgarPlanPaywallModel

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            sheet(content)
        } else {
            content
        }
        #else
        sheet(content)
        #endif
    }

    #if !os(tvOS)
    @available(macOS 15.0, *)
    private func sheet(_ content: Content) -> some View {
        content.offerCodeRedemption(isPresented: $model.isPresentingOfferCodeSheet) { result in
            Task { await model.offerCodeSheetFinished(result) }
        }
    }
    #endif
}
