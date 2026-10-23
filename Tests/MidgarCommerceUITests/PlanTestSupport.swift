import Foundation
@testable import MidgarCommerce
@testable import MidgarCommerceUI

enum PlanFixtures {
    static let yearly = "app.midgar.test.yearly"
    static let monthly = "app.midgar.test.monthly"
    static let lifetime = "app.midgar.test.lifetime"
    static let english = Locale(identifier: "en_US")

    static func product(_ id: String, name: String, price: Decimal, display: String, currency: String? = "USD", family: Bool = false) -> StoreProduct {
        StoreProduct(id: id, displayName: name, description: "", displayPrice: display, price: price, isFamilyShareable: family, currencyCode: currency)
    }

    static func terms(_ id: String, display: String, period: MidgarBillingPeriod, intro: MidgarIntroOffer? = nil) -> MidgarSubscriptionTerms {
        MidgarSubscriptionTerms(productID: id, groupID: "group", displayPrice: display, period: period, introOffer: intro)
    }

    static let weekFree = MidgarIntroOffer(kind: .freeTrial, period: MidgarBillingPeriod(value: 1, unit: .week), periodCount: 1, displayPrice: "$0.00")

    static func trial(_ id: String, offer: MidgarIntroOffer = weekFree, renewal: String = "$39.99/year") -> MidgarTrialPresentation {
        MidgarTrialPresentation(
            productID: id,
            offer: offer,
            renewalDescription: renewal,
            summary: "1 week free, then \(renewal)",
            badge: offer.kind == .freeTrial ? "1 week free" : nil
        )
    }

    static let yearlyProduct = product(yearly, name: "Yearly", price: 39.99, display: "$39.99")
    static let monthlyProduct = product(monthly, name: "Monthly", price: 4.99, display: "$4.99")
    static let lifetimeProduct = product(lifetime, name: "Lifetime", price: 79.99, display: "$79.99", family: true)
    static let yearlyTerms = terms(yearly, display: "$39.99", period: MidgarBillingPeriod(value: 1, unit: .year), intro: weekFree)
    static let monthlyTerms = terms(monthly, display: "$4.99", period: MidgarBillingPeriod(value: 1, unit: .month))

    static func catalog(
        products: [StoreProduct] = [yearlyProduct, monthlyProduct, lifetimeProduct],
        terms: [MidgarSubscriptionTerms] = [yearlyTerms, monthlyTerms],
        presentations: [String: MidgarTrialPresentation] = [yearly: trial(yearly)],
        order: [String] = [yearly, monthly, lifetime],
        featured: String? = nil,
        names: [String: String] = [:],
        oneTimeNote: String? = nil,
        locale: Locale = english
    ) -> MidgarPlanCatalog {
        MidgarPlanCatalog.make(products: products, terms: terms, presentations: presentations, order: order, featuredID: featured, names: names, oneTimeNote: oneTimeNote, locale: locale)
    }
}
