import MidgarUI
import SwiftUI

/// One benefit row of a paywall: a symbol, a title and an optional line of detail. The app supplies the words, already localized.
public struct MidgarPaywallFeature: Sendable, Equatable, Identifiable {
    public let symbol: String
    public let title: String
    public let detail: String?

    public var id: String { symbol + "|" + title }

    public init(symbol: String, title: String, detail: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// The picture at the top of a paywall.
public enum MidgarPaywallArtwork: Sendable {
    /// An SF Symbol in the accent.
    case symbol(String)
    /// An image the app draws, shown in a rounded frame.
    case image(Image)
}

/// What the app says at the top of a plan paywall: the picture, the headline, the subtitle and the benefit rows.
public struct MidgarPaywallHero: Sendable {
    public let title: String
    public let subtitle: String?
    public let artwork: MidgarPaywallArtwork?
    public let features: [MidgarPaywallFeature]

    public init(title: String, subtitle: String? = nil, artwork: MidgarPaywallArtwork? = nil, features: [MidgarPaywallFeature] = []) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.features = features
    }
}

/// What a plan paywall sells and what it says. The one value ``MidgarPlanPaywall`` and the UIKit host are built from.
public struct MidgarPlanPaywallConfiguration: Sendable {
    /// The subscriptions and one-time products to sell, in display order. Each must be one of the store's configured products. A product that is an auto-renewable subscription is sold as a subscription, any other as a one-time purchase.
    public let productIDs: [String]
    public let links: MidgarPaywallLinks
    public let hero: MidgarPaywallHero
    /// The plan that opens selected. Without one, the first plan with a free trial the customer may use, else the first subscription.
    public let featuredProductID: String?
    /// The accent of this paywall. Without one, the theme's accent.
    public let accent: MidgarColor?
    /// Whether the app posts a reminder before a free trial ends. The trial timeline shows the reminder step only when this is true, so set it false when the app does not post one. tvOS never shows the step, because it has no notifications to post.
    public let promisesTrialReminder: Bool

    public init(
        productIDs: [String],
        links: MidgarPaywallLinks,
        hero: MidgarPaywallHero,
        featuredProductID: String? = nil,
        accent: MidgarColor? = nil,
        promisesTrialReminder: Bool = true
    ) {
        self.productIDs = productIDs
        self.links = links
        self.hero = hero
        self.featuredProductID = featuredProductID
        self.accent = accent
        self.promisesTrialReminder = promisesTrialReminder
    }

    var showsTrialReminder: Bool {
        #if os(tvOS)
        false
        #else
        promisesTrialReminder
        #endif
    }
}
