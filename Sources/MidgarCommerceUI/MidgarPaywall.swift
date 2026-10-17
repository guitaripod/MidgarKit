import MidgarCommerce
import MidgarUI
import StoreKit
import SwiftUI

/// A subscription paywall for one subscription group, built on `SubscriptionStoreView` and styled with the Midgar theme.
///
/// StoreKit draws the plans, their prices and periods, the offer text for an eligible customer and the purchase button; the footer adds what App Review requires on every paywall (guideline 3.1.2): the price and period of each plan from StoreKit, the auto-renew terms, Terms of Use and Privacy Policy links the app passes in, and Restore Purchases. StoreKit's own Restore and policy buttons are hidden so the footer's are the only ones, and Restore runs ``MidgarStore/restore()`` so restored purchases reach the ledger.
///
/// Purchases belong to the ``MidgarStore``: see ``SwiftUI/View/midgarPurchases(store:onEvent:)``. visionOS needs nothing extra, because the StoreKit view anchors its sheet to its own scene.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPaywall<Marketing: View>: View {
    private let groupID: String
    private let store: MidgarStore
    private let links: MidgarPaywallLinks
    private let marketing: Marketing
    @State private var model: MidgarPaywallModel
    @Environment(\.midgarTheme) private var theme

    /// - Parameters:
    ///   - groupID: The subscription group id from App Store Connect.
    ///   - store: The app's store. Its configured products must include the group's subscriptions.
    ///   - links: The app's Terms of Use and Privacy Policy.
    ///   - trialPolicy: Where offers and renewal prices come from. The default asks StoreKit.
    ///   - onEvent: Called on the main actor for every outcome. Close the paywall on ``MidgarPaywallEvent/isSuccess``.
    ///   - marketing: The header above the plans.
    public init(
        groupID: String,
        store: MidgarStore,
        links: MidgarPaywallLinks,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in },
        @ViewBuilder marketing: () -> Marketing
    ) {
        self.groupID = groupID
        self.store = store
        self.links = links
        self.marketing = marketing()
        _model = State(initialValue: MidgarPaywallModel(store: store, trialPolicy: trialPolicy, groupID: groupID, onEvent: onEvent))
    }

    public var body: some View {
        VStack(spacing: 0) {
            storeView
            MidgarPaywallFooter(
                planLines: model.planLines,
                showsAutoRenew: true,
                links: links,
                isRestoring: model.isRestoring,
                restore: { Task { await model.restore() } }
            )
        }
        .background(theme.background.color.ignoresSafeArea())
        .midgarToast($model.toast)
        .midgarFailureAlert($model.failureMessage)
        .task { await model.loadPlans() }
    }

    private var storeView: some View {
        SubscriptionStoreView(groupID: groupID) {
            marketing
        }
        .storeButton(.hidden, for: .restorePurchases, .policies)
        .tint(theme.accent.color)
        .midgarStoreChrome()
        .midgarPurchases(store: store) { model.receive($0) }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension MidgarPaywall where Marketing == MidgarPaywallHeader {
    /// A paywall with the standard header: an optional symbol, a title and a subtitle, all supplied (and localized) by the app.
    public init(
        groupID: String,
        store: MidgarStore,
        links: MidgarPaywallLinks,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in }
    ) {
        self.init(groupID: groupID, store: store, links: links, trialPolicy: trialPolicy, onEvent: onEvent) {
            MidgarPaywallHeader(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }
}

/// The standard header of a paywall: a symbol in the accent, a title and a subtitle.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPaywallHeader: View {
    public let title: String
    public let subtitle: String?
    public let systemImage: String?

    @Environment(\.midgarTheme) private var theme

    public init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: theme.spacing.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 48))
                    .foregroundStyle(theme.accent.color)
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
                .midgarFont(.title)
                .foregroundStyle(theme.label.color)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(verbatim: subtitle)
                    .midgarFont(.body)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension View {
    /// An alert with the generic failure title and `message` while it is non-nil.
    func midgarFailureAlert(_ message: Binding<String?>) -> some View {
        alert(
            MidgarCommerceUIStrings.failureTitle,
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            presenting: message.wrappedValue
        ) { _ in
            Button(MidgarCommerceUIStrings.ok, role: .cancel) {}
        } message: { text in
            Text(verbatim: text)
        }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarStoreChrome: ViewModifier {
    @Environment(\.midgarTheme) private var theme

    /// The theme's surface behind each plan of the picker, in the theme's corner radius where StoreKit lets the shape be set (iOS 18 and later), and its background behind the whole store view. tvOS has no picker background and visionOS no full-height container background.
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.containerBackground(theme.background.color, for: .subscriptionStoreFullHeight)
        #elseif os(visionOS)
        pickerItems(content)
        #else
        pickerItems(content).containerBackground(theme.background.color, for: .subscriptionStoreFullHeight)
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    private func pickerItems(_ content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
            content.subscriptionStorePickerItemBackground(
                theme.surface.color,
                in: RoundedRectangle(cornerRadius: theme.radius.medium, style: .continuous)
            )
        } else {
            content.subscriptionStorePickerItemBackground(theme.surface.color)
        }
    }
    #endif
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension View {
    func midgarStoreChrome() -> some View {
        modifier(MidgarStoreChrome())
    }
}
