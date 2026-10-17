import Foundation

/// What a paywall may say about a subscription's introductory offer for this customer. It exists only when StoreKit says the customer is eligible and the product carries an offer.
public struct MidgarTrialPresentation: Sendable, Equatable {
    public let productID: String
    public let offer: MidgarIntroOffer
    /// The renewal price with its period, e.g. `$39.99/year`.
    public let renewalDescription: String
    /// The offer and what follows it in one line, e.g. `1 week free, then $39.99/year`.
    public let summary: String
    /// A short label for a plan that starts with a free trial, e.g. `1 week free`. Nil for a paid introductory offer.
    public let badge: String?

    public var isFreeTrial: Bool {
        offer.kind == .freeTrial
    }
}

/// The one trial policy of every Midgar app: present an introductory offer exactly when StoreKit says this customer is eligible for it, and say exactly what the product's own offer data says.
///
/// Eligibility is `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` per subscription group and nothing else: no flag of ours, no counter, no first-launch date. A customer who used the offer, in this app or on another device of the Apple Account, is not eligible and sees only the renewal price. The text comes from the product's offer (kind, period, period count, price) and the renewal price, never from a constant, so changing the offer in App Store Connect changes the paywall.
///
/// Eligibility changes after a purchase and after a restore, so ask again then; the policy keeps no cache.
public struct MidgarTrialPolicy: Sendable {
    private let source: any MidgarSubscriptionSource
    private let locale: Locale

    /// The policy over StoreKit and the customer's locale.
    public init() {
        self.init(source: LiveSubscriptionSource(), locale: .current)
    }

    init(source: any MidgarSubscriptionSource, locale: Locale) {
        self.source = source
        self.locale = locale
    }

    /// StoreKit's answer for a subscription group.
    public func isEligibleForIntroOffer(inGroup groupID: String) async -> Bool {
        await source.isEligibleForIntroOffer(groupID: groupID)
    }

    /// The offer to present for each product that has one the customer may use, keyed by product id. A product without an offer, in a group the customer is not eligible for, or that StoreKit does not sell is absent. Throws when StoreKit cannot load the products.
    public func presentations(for productIDs: [String]) async throws -> [String: MidgarTrialPresentation] {
        let terms = try await source.terms(for: productIDs)
        var eligibility: [String: Bool] = [:]
        var found: [String: MidgarTrialPresentation] = [:]
        for term in terms where term.introOffer != nil {
            if eligibility[term.groupID] == nil {
                eligibility[term.groupID] = await source.isEligibleForIntroOffer(groupID: term.groupID)
            }
            if eligibility[term.groupID] == true, let presentation = presentation(for: term) {
                found[term.productID] = presentation
            }
        }
        return found
    }

    /// The offer to present for one product, or nil when there is none for this customer.
    public func presentation(for productID: String) async throws -> MidgarTrialPresentation? {
        try await presentations(for: [productID])[productID]
    }

    /// What each auto-renewable subscription among `productIDs` charges, in the order of `productIDs`. Products that are not subscriptions or that StoreKit does not sell are absent.
    public func terms(for productIDs: [String]) async throws -> [MidgarSubscriptionTerms] {
        try await source.terms(for: productIDs)
    }

    private func presentation(for terms: MidgarSubscriptionTerms) -> MidgarTrialPresentation? {
        guard let offer = terms.introOffer else {
            return nil
        }
        let renewal = terms.renewalDescription(locale: locale)
        let duration = MidgarPeriodFormatter.phrase(offer.totalDuration, locale: locale)
        switch offer.kind {
        case .freeTrial:
            return MidgarTrialPresentation(
                productID: terms.productID,
                offer: offer,
                renewalDescription: renewal,
                summary: MidgarCommerceStrings.freeThenRecurring(duration, renewal, locale: locale),
                badge: MidgarCommerceStrings.trialBadge(duration, locale: locale)
            )
        case .payAsYouGo:
            let perPeriod = MidgarPeriodFormatter.price(offer.displayPrice, per: offer.period, locale: locale)
            return MidgarTrialPresentation(
                productID: terms.productID,
                offer: offer,
                renewalDescription: renewal,
                summary: MidgarCommerceStrings.introThenRecurring(perPeriod, duration, renewal, locale: locale),
                badge: nil
            )
        case .payUpFront:
            return MidgarTrialPresentation(
                productID: terms.productID,
                offer: offer,
                renewalDescription: renewal,
                summary: MidgarCommerceStrings.introThenRecurring(offer.displayPrice, duration, renewal, locale: locale),
                badge: nil
            )
        }
    }
}

extension MidgarSubscriptionTerms {
    /// The renewal price with its period, e.g. `$39.99/year`, or `$9.99 every 3 months` for a period longer than one unit.
    public func renewalDescription(locale: Locale = .current) -> String {
        MidgarPeriodFormatter.price(displayPrice, per: period, locale: locale)
    }
}

/// Turns periods and prices into the words a paywall shows, in the customer's locale.
enum MidgarPeriodFormatter {
    /// `$4.99/month` for one unit, `$9.99 every 3 months` for more.
    static func price(_ price: String, per period: MidgarBillingPeriod, locale: Locale) -> String {
        if period.value == 1 {
            return MidgarCommerceStrings.pricePerUnit(price, MidgarCommerceStrings.unitName(period.unit, locale: locale), locale: locale)
        }
        return MidgarCommerceStrings.priceEvery(price, phrase(period, locale: locale), locale: locale)
    }

    /// `1 week`, `3 months`: the period spelled out and localized by Foundation.
    static func phrase(_ period: MidgarBillingPeriod, locale: Locale) -> String {
        var components = DateComponents()
        let formatter = DateComponentsFormatter()
        switch period.unit {
        case .day:
            components.day = period.value
            formatter.allowedUnits = [.day]
        case .week:
            components.weekOfMonth = period.value
            formatter.allowedUnits = [.weekOfMonth]
        case .month:
            components.month = period.value
            formatter.allowedUnits = [.month]
        case .year:
            components.year = period.value
            formatter.allowedUnits = [.year]
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        return formatter.string(from: components) ?? "\(period.value) \(period.unit.rawValue)"
    }
}
