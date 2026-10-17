import MidgarCommerce
import MidgarUI
import StoreKit
import SwiftUI

/// A paywall for one-time products (a lifetime unlock, a pack), built on `StoreView` and drawing every product as a ``MidgarPlanCard``.
///
/// Prices come from StoreKit. The footer carries Terms of Use, Privacy Policy and Restore Purchases; it states no auto-renew terms, because these products do not renew. Purchases belong to the ``MidgarStore`` through ``SwiftUI/View/midgarPurchases(store:onEvent:)``.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarStorefront<Header: View>: View {
    private let productIDs: [String]
    private let store: MidgarStore
    private let links: MidgarPaywallLinks
    private let header: Header
    @State private var model: MidgarPaywallModel
    @Environment(\.midgarTheme) private var theme

    /// - Parameters:
    ///   - productIDs: The one-time products to sell, in display order. Each must be one of the store's configured products.
    ///   - store: The app's store.
    ///   - links: The app's Terms of Use and Privacy Policy.
    ///   - onEvent: Called on the main actor for every outcome. Close the storefront on ``MidgarPaywallEvent/isSuccess``.
    ///   - header: The header above the products.
    public init(
        productIDs: [String],
        store: MidgarStore,
        links: MidgarPaywallLinks,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in },
        @ViewBuilder header: () -> Header
    ) {
        self.productIDs = productIDs
        self.store = store
        self.links = links
        self.header = header()
        _model = State(initialValue: MidgarPaywallModel(store: store, trialPolicy: MidgarTrialPolicy(), groupID: nil, productIDs: Set(productIDs), onEvent: onEvent))
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: theme.spacing.l) {
                    header
                    StoreView(ids: productIDs)
                        .productViewStyle(MidgarPlanProductViewStyle())
                        .storeButton(.hidden, for: .restorePurchases)
                        .midgarPurchases(store: store) { model.receive($0) }
                        .padding(.horizontal, theme.spacing.l)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            MidgarPaywallFooter(
                planLines: model.planLines,
                showsAutoRenew: !model.planLines.isEmpty,
                links: links,
                isRestoring: model.isRestoring,
                restore: { Task { await model.restore() } }
            )
        }
        .background(theme.background.color.ignoresSafeArea())
        .tint(theme.accent.color)
        .midgarToast($model.toast)
        .midgarFailureAlert($model.failureMessage)
        .task { await model.loadPlans() }
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension MidgarStorefront where Header == MidgarPaywallHeader {
    /// A storefront with the standard header supplied (and localized) by the app.
    public init(
        productIDs: [String],
        store: MidgarStore,
        links: MidgarPaywallLinks,
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in }
    ) {
        self.init(productIDs: productIDs, store: store, links: links, onEvent: onEvent) {
            MidgarPaywallHeader(title: title, subtitle: subtitle, systemImage: systemImage)
        }
    }
}
