import Foundation
import StoreKit

/// The unit of a subscription or offer period, mirroring StoreKit's own so the policy and its tests do not depend on a `Product`.
public enum MidgarPeriodUnit: String, Sendable, Equatable, CaseIterable {
    case day
    case week
    case month
    case year
}

/// A length of time in whole units, as StoreKit reports a billing or offer period.
public struct MidgarBillingPeriod: Sendable, Equatable {
    public let value: Int
    public let unit: MidgarPeriodUnit

    public init(value: Int, unit: MidgarPeriodUnit) {
        self.value = value
        self.unit = unit
    }

    /// This period repeated `count` times, still in the same unit.
    func repeated(_ count: Int) -> MidgarBillingPeriod {
        MidgarBillingPeriod(value: value * max(count, 1), unit: unit)
    }
}

/// An introductory offer exactly as the product carries it. Nothing here is decided by the app.
public struct MidgarIntroOffer: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case freeTrial
        case payAsYouGo
        case payUpFront
    }

    public let kind: Kind
    /// The length of one offer period.
    public let period: MidgarBillingPeriod
    /// How many offer periods the offer lasts. A free trial and a pay-up-front offer have one.
    public let periodCount: Int
    /// The price of the offer in the customer's storefront currency, per period for pay as you go and for the whole offer when paid up front. StoreKit's own string.
    public let displayPrice: String

    public init(kind: Kind, period: MidgarBillingPeriod, periodCount: Int, displayPrice: String) {
        self.kind = kind
        self.period = period
        self.periodCount = periodCount
        self.displayPrice = displayPrice
    }

    /// How long the whole offer lasts.
    public var totalDuration: MidgarBillingPeriod {
        period.repeated(periodCount)
    }
}

/// What one auto-renewable subscription charges and, if it has one, the introductory offer it carries. Whether the customer may use that offer is a separate question StoreKit answers per subscription group.
public struct MidgarSubscriptionTerms: Sendable, Equatable {
    public let productID: String
    public let groupID: String
    /// The renewal price in the customer's storefront currency, StoreKit's own string.
    public let displayPrice: String
    public let period: MidgarBillingPeriod
    public let introOffer: MidgarIntroOffer?

    public init(productID: String, groupID: String, displayPrice: String, period: MidgarBillingPeriod, introOffer: MidgarIntroOffer?) {
        self.productID = productID
        self.groupID = groupID
        self.displayPrice = displayPrice
        self.period = period
        self.introOffer = introOffer
    }

    /// The terms StoreKit reports for a product, or nil when it is not an auto-renewable subscription.
    public init?(product: Product) {
        guard let terms = LiveSubscriptionSource.terms(of: product) else {
            return nil
        }
        self = terms
    }
}

/// The two StoreKit questions the trial policy asks, so its logic runs against fakes in unit tests and against ``LiveSubscriptionSource`` in the app.
protocol MidgarSubscriptionSource: Sendable {
    func terms(for productIDs: [String]) async throws -> [MidgarSubscriptionTerms]
    func isEligibleForIntroOffer(groupID: String) async -> Bool
}

/// The production source: `Product.products(for:)` for the terms and `Product.SubscriptionInfo.isEligibleForIntroOffer(for:)` for eligibility, with no decisions of its own.
struct LiveSubscriptionSource: MidgarSubscriptionSource {
    func terms(for productIDs: [String]) async throws -> [MidgarSubscriptionTerms] {
        let products = try await Product.products(for: productIDs)
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return productIDs.compactMap { id in
            byID[id].flatMap(Self.terms(of:))
        }
    }

    func isEligibleForIntroOffer(groupID: String) async -> Bool {
        await Product.SubscriptionInfo.isEligibleForIntroOffer(for: groupID)
    }

    /// Nil for a product that is not an auto-renewable subscription.
    static func terms(of product: Product) -> MidgarSubscriptionTerms? {
        guard let info = product.subscription else {
            return nil
        }
        return MidgarSubscriptionTerms(
            productID: product.id,
            groupID: info.subscriptionGroupID,
            displayPrice: product.displayPrice,
            period: period(of: info.subscriptionPeriod),
            introOffer: info.introductoryOffer.map(offer(of:))
        )
    }

    private static func offer(of offer: Product.SubscriptionOffer) -> MidgarIntroOffer {
        MidgarIntroOffer(
            kind: kind(of: offer.paymentMode),
            period: period(of: offer.period),
            periodCount: offer.periodCount,
            displayPrice: offer.displayPrice
        )
    }

    private static func kind(of mode: Product.SubscriptionOffer.PaymentMode) -> MidgarIntroOffer.Kind {
        if mode == .freeTrial {
            return .freeTrial
        }
        if mode == .payUpFront {
            return .payUpFront
        }
        return .payAsYouGo
    }

    private static func period(of period: Product.SubscriptionPeriod) -> MidgarBillingPeriod {
        MidgarBillingPeriod(value: period.value, unit: unit(of: period.unit))
    }

    private static func unit(of unit: Product.SubscriptionPeriod.Unit) -> MidgarPeriodUnit {
        switch unit {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        @unknown default: return .month
        }
    }
}
