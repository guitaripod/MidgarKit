import Foundation
import MidgarCommerce

/// One choice of the plan picker: an auto-renewable subscription or a one-time product, with every line the picker states for it.
struct MidgarPlan: Identifiable, Equatable {
    enum Kind: Equatable {
        case subscription(MidgarSubscriptionTerms)
        case oneTime
    }

    let id: String
    let name: String
    let displayPrice: String
    let kind: Kind
    /// The lines under the name, in order: the offer or the billing, the monthly equivalent, Family Sharing.
    let detailLines: [String]
    let badge: String?
    /// The introductory offer StoreKit lets this customer use, nil when there is none.
    let trial: MidgarTrialPresentation?
    /// The line above the purchase button.
    let offerLine: String
    let ctaTitle: String

    var isSubscription: Bool {
        if case .subscription = kind {
            return true
        }
        return false
    }

    /// Price, then the detail lines, for VoiceOver.
    var accessibilityLabel: String {
        ([name, displayPrice] + detailLines).joined(separator: ", ")
    }
}

/// The plans of a paywall in display order, the caption that compares the one-time product with the yearly plan, and which plan opens selected.
struct MidgarPlanCatalog: Equatable {
    var plans: [MidgarPlan]
    var lifetimeAnchor: String?
    var preselectedID: String?

    static let empty = MidgarPlanCatalog(plans: [], lifetimeAnchor: nil, preselectedID: nil)

    func plan(id: String?) -> MidgarPlan? {
        plans.first { $0.id == id }
    }

    /// Builds the catalog from what StoreKit reports.
    ///
    /// - Parameters:
    ///   - products: The store's products with their prices. A product the store does not sell is skipped.
    ///   - terms: The subscription terms of the products that are subscriptions. A product without terms is a one-time product.
    ///   - presentations: The introductory offers this customer may use, by product id.
    ///   - order: The product ids in display order.
    ///   - featuredID: The plan that opens selected. Without one, the first plan with a free trial, else the first subscription, else the first plan.
    static func make(
        products: [StoreProduct],
        terms: [MidgarSubscriptionTerms],
        presentations: [String: MidgarTrialPresentation],
        order: [String],
        featuredID: String? = nil,
        locale: Locale = .current
    ) -> MidgarPlanCatalog {
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let termsByID = Dictionary(terms.map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = order.compactMap { productsByID[$0] }
        let monthly = ordered.first { termsByID[$0.id]?.period.isMonth == true }
        let annual = ordered.first { termsByID[$0.id]?.period.isYear == true }
        let plans = ordered.map { product in
            makePlan(product, terms: termsByID[product.id], presentation: presentations[product.id], monthly: monthly, locale: locale)
        }
        let oneTime = ordered.first { termsByID[$0.id] == nil }
        return MidgarPlanCatalog(
            plans: plans,
            lifetimeAnchor: lifetimeAnchor(oneTime: oneTime, annual: annual, locale: locale),
            preselectedID: preselectedID(in: plans, featuredID: featuredID)
        )
    }

    private static func preselectedID(in plans: [MidgarPlan], featuredID: String?) -> String? {
        if let featuredID, plans.contains(where: { $0.id == featuredID }) {
            return featuredID
        }
        return (plans.first { $0.trial?.isFreeTrial == true } ?? plans.first { $0.isSubscription } ?? plans.first)?.id
    }

    private static func makePlan(
        _ product: StoreProduct,
        terms: MidgarSubscriptionTerms?,
        presentation: MidgarTrialPresentation?,
        monthly: StoreProduct?,
        locale: Locale
    ) -> MidgarPlan {
        guard let terms else {
            return makeOneTimePlan(product)
        }
        let renewal = terms.renewalDescription(locale: locale)
        let months = terms.period.wholeMonths
        let percent = months.flatMap { months in
            monthly.flatMap { MidgarPlanCaptions.savingsPercent(price: product.price, months: months, monthlyPrice: $0.price) }
        }
        let badge = percent.map { MidgarCommerceUIStrings.saveBadge(MidgarPlanCaptions.formatPercent($0, locale: locale)) } ?? presentation?.badge
        let summary = presentation?.summary
        let lines = [summary ?? MidgarCommerceUIStrings.cancelAnytime(renewal), equivalentLine(product, terms: terms, locale: locale)]
        return MidgarPlan(
            id: product.id,
            name: product.displayName,
            displayPrice: product.displayPrice,
            kind: .subscription(terms),
            detailLines: lines.compactMap { $0 } + familyLine(product),
            badge: badge,
            trial: presentation,
            offerLine: summary ?? renewal,
            ctaTitle: ctaTitle(for: presentation)
        )
    }

    /// "Try 1 week free" for a free trial the customer may use, "Continue" otherwise.
    private static func ctaTitle(for presentation: MidgarTrialPresentation?) -> String {
        guard let presentation, presentation.isFreeTrial, let offer = presentation.badge else {
            return MidgarCommerceUIStrings.continueButton
        }
        return MidgarCommerceUIStrings.tryFree(offer)
    }

    private static func makeOneTimePlan(_ product: StoreProduct) -> MidgarPlan {
        MidgarPlan(
            id: product.id,
            name: product.displayName,
            displayPrice: product.displayPrice,
            kind: .oneTime,
            detailLines: [MidgarCommerceUIStrings.payOnceKeepForever] + familyLine(product),
            badge: nil,
            trial: nil,
            offerLine: MidgarCommerceUIStrings.oneTimeOffer(product.displayPrice),
            ctaTitle: MidgarCommerceUIStrings.continueButton
        )
    }

    private static func familyLine(_ product: StoreProduct) -> [String] {
        product.isFamilyShareable ? [MidgarCommerceUIStrings.familySharingIncluded] : []
    }

    /// What a plan longer than a month works out to per month, which is what makes it comparable with the monthly plan at a glance.
    private static func equivalentLine(_ product: StoreProduct, terms: MidgarSubscriptionTerms, locale: Locale) -> String? {
        guard let months = terms.period.wholeMonths, months > 1,
              let equivalent = MidgarPlanCaptions.monthlyEquivalent(price: product.price, months: months),
              let text = MidgarPlanCaptions.format(equivalent, currencyCode: product.currencyCode, locale: product.priceLocale ?? locale) else {
            return nil
        }
        return terms.period.isYear ? MidgarCommerceUIStrings.perMonthBilledYearly(text) : MidgarCommerceUIStrings.perMonth(text)
    }

    private static func lifetimeAnchor(oneTime: StoreProduct?, annual: StoreProduct?, locale: Locale) -> String? {
        guard let oneTime, let annual,
              let years = MidgarPlanCaptions.lifetimeYears(lifetimePrice: oneTime.price, annualPrice: annual.price),
              let total = MidgarPlanCaptions.format(MidgarPlanCaptions.rounded(annual.price * years, scale: 2), currencyCode: annual.currencyCode, locale: annual.priceLocale ?? locale) else {
            return nil
        }
        return MidgarCommerceUIStrings.lifetimeAnchor(
            years: MidgarPlanCaptions.formatYears(years, locale: locale),
            annualName: annual.displayName,
            total: total,
            lifetimeName: oneTime.displayName,
            lifetimePrice: oneTime.displayPrice
        )
    }
}

/// Which plan of a catalog is selected. A choice survives a reload while its plan is still sold, falls back to the catalog's preselection when it is not, and cannot change while a purchase or restore runs.
struct MidgarPlanSelection: Equatable {
    private(set) var selectedID: String?

    /// Keeps the current choice when `catalog` still sells it, else takes the catalog's preselection.
    mutating func reconcile(with catalog: MidgarPlanCatalog) {
        if catalog.plan(id: selectedID) == nil {
            selectedID = catalog.preselectedID
        }
    }

    /// Selects `id` when the catalog sells it and nothing is in flight. Returns whether the selection changed hands.
    @discardableResult
    mutating func select(_ id: String, in catalog: MidgarPlanCatalog, isBusy: Bool) -> Bool {
        guard !isBusy, catalog.plan(id: id) != nil else {
            return false
        }
        selectedID = id
        return true
    }
}
