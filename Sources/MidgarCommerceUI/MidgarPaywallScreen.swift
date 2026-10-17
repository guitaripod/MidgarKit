import MidgarCommerce
import SwiftUI

/// What a paywall sells and what it says. The one value both the SwiftUI screen and the UIKit host are built from.
public struct MidgarPaywallConfiguration: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// An auto-renewable subscription group, sold with `SubscriptionStoreView`.
        case subscriptions(groupID: String)
        /// One-time products, sold with `StoreView`.
        case products(ids: [String])
    }

    public let kind: Kind
    public let links: MidgarPaywallLinks
    public let title: String
    public let subtitle: String?
    public let systemImage: String?

    public init(kind: Kind, links: MidgarPaywallLinks, title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.kind = kind
        self.links = links
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }
}

/// The paywall for a ``MidgarPaywallConfiguration``: ``MidgarPaywall`` for a subscription group, ``MidgarStorefront`` for one-time products.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
public struct MidgarPaywallScreen: View {
    private let configuration: MidgarPaywallConfiguration
    private let store: MidgarStore
    private let trialPolicy: MidgarTrialPolicy
    private let onEvent: @MainActor (MidgarPaywallEvent) -> Void

    public init(
        configuration: MidgarPaywallConfiguration,
        store: MidgarStore,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.store = store
        self.trialPolicy = trialPolicy
        self.onEvent = onEvent
    }

    @ViewBuilder
    public var body: some View {
        switch configuration.kind {
        case .subscriptions(let groupID):
            MidgarPaywall(
                groupID: groupID,
                store: store,
                links: configuration.links,
                title: configuration.title,
                subtitle: configuration.subtitle,
                systemImage: configuration.systemImage,
                trialPolicy: trialPolicy,
                onEvent: onEvent
            )
        case .products(let ids):
            MidgarStorefront(
                productIDs: ids,
                store: store,
                links: configuration.links,
                title: configuration.title,
                subtitle: configuration.subtitle,
                systemImage: configuration.systemImage,
                onEvent: onEvent
            )
        }
    }
}
