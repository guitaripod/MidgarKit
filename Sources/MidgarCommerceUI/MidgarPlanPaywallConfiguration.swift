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
    /// An SF Symbol that turns into a lightly blurred picture with the symbol over it once `load` returns one, such as the picture the customer was stopped at. A picture that never arrives leaves the symbol alone, as if none had been asked for. `load` runs on the main actor when the paywall appears.
    case picture(symbol: String, load: @Sendable @MainActor () async -> Image?)

    var isSymbolOnly: Bool {
        if case .symbol = self {
            return true
        }
        return false
    }
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
    /// Colors of a gradient drawn from the top leading corner to the bottom trailing one over the theme's background, behind the whole paywall, the pinned purchase bar included. Empty draws the plain background.
    public let backdrop: [MidgarColor]
    /// The names the picker shows, by product id, in place of the store's display names. A product without an entry keeps its display name. The comparison caption uses them too.
    public let planNames: [String: String]
    /// A sentence the app adds to the offer line of a one-time product, such as where the purchase works.
    public let oneTimeNote: String?
    /// Whether the customer owns something the store cannot see, such as an earlier paid version of the app. Asked after a restore found nothing in the store: a true answer makes the outcome ``MidgarPaywallEvent/restored`` instead of ``MidgarPaywallEvent/nothingToRestore``.
    public let ownsPurchaseOutsideStore: (@Sendable @MainActor () async -> Bool)?
    /// Whether the footer offers to redeem an offer code. Turn it on where the platform has the App Store's redemption sheet (iOS, visionOS and macOS).
    public let offersCodeRedemption: Bool

    public init(
        productIDs: [String],
        links: MidgarPaywallLinks,
        hero: MidgarPaywallHero,
        featuredProductID: String? = nil,
        accent: MidgarColor? = nil,
        promisesTrialReminder: Bool = true,
        backdrop: [MidgarColor] = [],
        planNames: [String: String] = [:],
        oneTimeNote: String? = nil,
        offersCodeRedemption: Bool = false,
        ownsPurchaseOutsideStore: (@Sendable @MainActor () async -> Bool)? = nil
    ) {
        self.productIDs = productIDs
        self.links = links
        self.hero = hero
        self.featuredProductID = featuredProductID
        self.accent = accent
        self.promisesTrialReminder = promisesTrialReminder
        self.backdrop = backdrop
        self.planNames = planNames
        self.oneTimeNote = oneTimeNote
        self.offersCodeRedemption = offersCodeRedemption
        self.ownsPurchaseOutsideStore = ownsPurchaseOutsideStore
    }

    var showsTrialReminder: Bool {
        #if os(tvOS)
        false
        #else
        promisesTrialReminder
        #endif
    }
}

/// A button that leaves the paywall, for a platform whose paywall has no close control of its own, such as the Apple TV remote's missing close button. It sits with Restore Purchases.
public struct MidgarPaywallDismissButton: Sendable {
    public let title: String
    public let action: @MainActor @Sendable () -> Void

    public init(title: String, action: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.action = action
    }
}
