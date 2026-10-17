import Foundation
import Testing
@testable import MidgarCommerce
@testable import MidgarCommerceUI

@Suite struct PlanCaptionTests {
    @Test func theMonthlyEquivalentIsRoundedToCents() {
        #expect(MidgarPlanCaptions.monthlyEquivalent(price: 39.99, months: 12) == Decimal(string: "3.33"))
        #expect(MidgarPlanCaptions.monthlyEquivalent(price: 19.99, months: 12) == Decimal(string: "1.67"))
        #expect(MidgarPlanCaptions.monthlyEquivalent(price: 12.99, months: 3) == Decimal(string: "4.33"))
        #expect(MidgarPlanCaptions.monthlyEquivalent(price: 0, months: 12) == nil)
        #expect(MidgarPlanCaptions.monthlyEquivalent(price: 39.99, months: 0) == nil)
    }

    @Test func theSavingsAreMeasuredAgainstMonthlyAndRoundedToAWholePercent() {
        #expect(MidgarPlanCaptions.savingsPercent(price: 39.99, months: 12, monthlyPrice: 4.99) == 33)
        #expect(MidgarPlanCaptions.savingsPercent(price: 19.99, months: 12, monthlyPrice: 2.99) == 44)
        #expect(MidgarPlanCaptions.savingsPercent(price: 12.99, months: 3, monthlyPrice: 4.99) == 13)
    }

    @Test func aPlanThatSavesNothingOrHasNoPriceStatesNoSaving() {
        #expect(MidgarPlanCaptions.savingsPercent(price: 59.99, months: 12, monthlyPrice: 4.99) == nil)
        #expect(MidgarPlanCaptions.savingsPercent(price: 0, months: 12, monthlyPrice: 4.99) == nil)
        #expect(MidgarPlanCaptions.savingsPercent(price: 39.99, months: 12, monthlyPrice: 0) == nil)
        #expect(MidgarPlanCaptions.savingsPercent(price: 4.99, months: 1, monthlyPrice: 4.99) == nil)
    }

    @Test func theLifetimeYearsRoundDownToAHalfYearSoTheCaptionNeverOverstates() {
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 49.99, annualPrice: 19.99) == Decimal(string: "2.5"))
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 49.99, annualPrice: 14.99) == Decimal(3))
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 100, annualPrice: 19.99) == Decimal(5))
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 79.99, annualPrice: 39.99) == Decimal(2))
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 29.99, annualPrice: 19.99) == Decimal(string: "1.5"))
    }

    @Test func aLifetimeThatIsNotClearlyDearerThanTheYearlyPlanGetsNoComparison() {
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 19.99, annualPrice: 19.99) == nil)
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 24.99, annualPrice: 19.99) == nil)
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 49.99, annualPrice: 0) == nil)
        #expect(MidgarPlanCaptions.lifetimeYears(lifetimePrice: 0, annualPrice: 19.99) == nil)
    }

    @Test func amountsAreFormattedInTheProductCurrencyAndTheCustomersLocale() {
        let german = Locale(identifier: "de_DE")
        #expect(MidgarPlanCaptions.format(Decimal(string: "3.33")!, currencyCode: "USD", locale: PlanFixtures.english) == "$3.33")
        #expect(MidgarPlanCaptions.format(Decimal(string: "3.33")!, currencyCode: "EUR", locale: german)?.contains("3,33") == true)
        #expect(MidgarPlanCaptions.format(Decimal(string: "3.33")!, currencyCode: nil, locale: german) == nil)
        #expect(MidgarPlanCaptions.formatPercent(33, locale: PlanFixtures.english) == "33%")
        #expect(MidgarPlanCaptions.formatYears(Decimal(2), locale: PlanFixtures.english) == "2")
        #expect(MidgarPlanCaptions.formatYears(Decimal(string: "2.5")!, locale: PlanFixtures.english) == "2.5")
    }

    @Test func onlyMonthsAndYearsCompareWithAMonthlyPrice() {
        #expect(MidgarBillingPeriod(value: 1, unit: .year).wholeMonths == 12)
        #expect(MidgarBillingPeriod(value: 3, unit: .month).wholeMonths == 3)
        #expect(MidgarBillingPeriod(value: 1, unit: .week).wholeMonths == nil)
        #expect(MidgarBillingPeriod(value: 7, unit: .day).wholeMonths == nil)
    }
}

@Suite struct PlanCatalogTests {
    private func plan(_ catalog: MidgarPlanCatalog, _ id: String) throws -> MidgarPlan {
        try #require(catalog.plan(id: id))
    }

    @Test func theCatalogListsSubscriptionsAndTheOneTimeProductInTheOrderTheAppGave() {
        let catalog = PlanFixtures.catalog()

        #expect(catalog.plans.map(\.id) == [PlanFixtures.yearly, PlanFixtures.monthly, PlanFixtures.lifetime])
        #expect(catalog.plans.map(\.isSubscription) == [true, true, false])
    }

    @Test func aProductStoreKitDoesNotSellIsLeftOut() {
        let catalog = PlanFixtures.catalog(products: [PlanFixtures.yearlyProduct, PlanFixtures.lifetimeProduct])

        #expect(catalog.plans.map(\.id) == [PlanFixtures.yearly, PlanFixtures.lifetime])
    }

    @Test func theYearlyPlanSaysWhatItSavesAgainstMonthlyFromStoreKitPrices() throws {
        let yearly = try plan(PlanFixtures.catalog(), PlanFixtures.yearly)

        #expect(yearly.badge == "Save 33%")
        #expect(yearly.detailLines == ["1 week free, then $39.99/year", "Just $3.33 a month, billed yearly"])
        #expect(yearly.displayPrice == "$39.99")
        #expect(yearly.ctaTitle == "Try 1 week free")
        #expect(yearly.offerLine == "1 week free, then $39.99/year")
    }

    @Test func aPlanWithoutAFreeTrialStatesItsRenewalPriceAndContinues() throws {
        let monthly = try plan(PlanFixtures.catalog(), PlanFixtures.monthly)

        #expect(monthly.badge == nil)
        #expect(monthly.detailLines == ["$4.99/month · cancel anytime"])
        #expect(monthly.offerLine == "$4.99/month")
        #expect(monthly.ctaTitle == "Continue")
    }

    @Test func aCustomerWhoUsedTheTrialSeesNoTrialAnywhere() throws {
        let catalog = PlanFixtures.catalog(presentations: [:])
        let yearly = try plan(catalog, PlanFixtures.yearly)

        #expect(yearly.trial == nil)
        #expect(yearly.detailLines.first == "$39.99/year · cancel anytime")
        #expect(yearly.ctaTitle == "Continue")
        #expect(yearly.badge == "Save 33%")
    }

    @Test func withoutAMonthlyPlanThereIsNoSavingAndTheTrialBecomesTheBadge() throws {
        let catalog = PlanFixtures.catalog(
            products: [PlanFixtures.yearlyProduct, PlanFixtures.lifetimeProduct],
            terms: [PlanFixtures.yearlyTerms],
            order: [PlanFixtures.yearly, PlanFixtures.lifetime]
        )
        let yearly = try plan(catalog, PlanFixtures.yearly)

        #expect(yearly.badge == "1 week free")
        #expect(yearly.detailLines.contains("Just $3.33 a month, billed yearly"))
    }

    @Test func theOneTimeProductIsComparedWithYearsOfTheYearlyPlan() throws {
        let catalog = PlanFixtures.catalog()
        let lifetime = try plan(catalog, PlanFixtures.lifetime)

        #expect(catalog.lifetimeAnchor == "2 years of Yearly costs $79.98. Lifetime is $79.99 and never renews.")
        #expect(lifetime.detailLines == ["Pay once. Keep it forever.", "Family Sharing included"])
        #expect(lifetime.offerLine == "One-time purchase of $79.99. No renewal.")
        #expect(lifetime.badge == nil)
        #expect(!lifetime.isSubscription)
    }

    @Test func withoutAYearlyPlanOrACurrencyThereIsNoComparison() {
        let noYearly = PlanFixtures.catalog(
            products: [PlanFixtures.monthlyProduct, PlanFixtures.lifetimeProduct],
            terms: [PlanFixtures.monthlyTerms],
            order: [PlanFixtures.monthly, PlanFixtures.lifetime]
        )
        let noCurrency = PlanFixtures.catalog(products: [
            PlanFixtures.product(PlanFixtures.yearly, name: "Yearly", price: 39.99, display: "$39.99", currency: nil),
            PlanFixtures.monthlyProduct,
            PlanFixtures.lifetimeProduct
        ])

        #expect(noYearly.lifetimeAnchor == nil)
        #expect(noCurrency.lifetimeAnchor == nil)
        #expect(noCurrency.plan(id: PlanFixtures.yearly)?.detailLines == ["1 week free, then $39.99/year"])
    }

    @Test func aProductStoreKitDidNotPriceGetsNoCaptionsAndNoCrash() throws {
        let unpriced = StoreProduct(id: PlanFixtures.yearly, displayName: "Yearly", description: "", displayPrice: "$39.99")
        let catalog = PlanFixtures.catalog(products: [unpriced, PlanFixtures.monthlyProduct, PlanFixtures.lifetimeProduct])
        let yearly = try plan(catalog, PlanFixtures.yearly)

        #expect(yearly.badge == "1 week free")
        #expect(yearly.detailLines == ["1 week free, then $39.99/year"])
        #expect(catalog.lifetimeAnchor == nil)
    }

    @Test func aLongerPlanThatIsNotAYearGetsTheMonthlyEquivalentWithoutTheYearlyWording() throws {
        let quarterly = PlanFixtures.product("app.midgar.test.quarterly", name: "Quarterly", price: 12.99, display: "$12.99")
        let terms = PlanFixtures.terms(quarterly.id, display: "$12.99", period: MidgarBillingPeriod(value: 3, unit: .month))
        let catalog = PlanFixtures.catalog(
            products: [quarterly, PlanFixtures.monthlyProduct],
            terms: [terms, PlanFixtures.monthlyTerms],
            presentations: [:],
            order: [quarterly.id, PlanFixtures.monthly]
        )
        let plan = try plan(catalog, quarterly.id)

        #expect(plan.badge == "Save 13%")
        #expect(plan.detailLines == ["$12.99 every 3 months · cancel anytime", "Just $4.33 a month"])
    }

    @Test func amountsAreFormattedInTheStorefrontLocaleOfTheProductNotTheDevices() throws {
        let storefront = Locale(identifier: "en_US")
        let yearly = StoreProduct(
            id: PlanFixtures.yearly, displayName: "Yearly", description: "", displayPrice: "$39.99",
            price: 39.99, currencyCode: "USD", priceLocale: storefront
        )
        let monthly = StoreProduct(
            id: PlanFixtures.monthly, displayName: "Monthly", description: "", displayPrice: "$4.99",
            price: 4.99, currencyCode: "USD", priceLocale: storefront
        )
        let catalog = PlanFixtures.catalog(products: [yearly, monthly], presentations: [:], order: [PlanFixtures.yearly, PlanFixtures.monthly], locale: Locale(identifier: "fi_FI"))

        #expect(catalog.plan(id: PlanFixtures.yearly)?.detailLines.contains("Just $3.33 a month, billed yearly") == true)
    }

    @Test func theCaptionsFollowTheStorefrontCurrencyAndLocale() throws {
        let german = Locale(identifier: "de_DE")
        let yearly = PlanFixtures.product(PlanFixtures.yearly, name: "Jährlich", price: 39.99, display: "39,99 €", currency: "EUR")
        let monthly = PlanFixtures.product(PlanFixtures.monthly, name: "Monatlich", price: 4.99, display: "4,99 €", currency: "EUR")
        let catalog = PlanFixtures.catalog(products: [yearly, monthly], presentations: [:], order: [PlanFixtures.yearly, PlanFixtures.monthly], locale: german)
        let plan = try plan(catalog, PlanFixtures.yearly)

        #expect(plan.detailLines.contains { $0.contains("3,33") })
        #expect(plan.badge?.contains("33") == true)
    }
}

@Suite struct PlanSelectionTests {
    @Test func theFeaturedPlanOpensSelectedWhenTheCatalogSellsIt() {
        #expect(PlanFixtures.catalog(featured: PlanFixtures.lifetime).preselectedID == PlanFixtures.lifetime)
        #expect(PlanFixtures.catalog(featured: PlanFixtures.monthly).preselectedID == PlanFixtures.monthly)
    }

    @Test func withoutAFeaturedPlanTheFirstFreeTrialOpensSelected() {
        #expect(PlanFixtures.catalog(order: [PlanFixtures.monthly, PlanFixtures.lifetime, PlanFixtures.yearly]).preselectedID == PlanFixtures.yearly)
    }

    @Test func withoutATrialTheFirstSubscriptionOpensSelectedAndAFeaturedPlanThatIsNotSoldIsIgnored() {
        let catalog = PlanFixtures.catalog(presentations: [:], order: [PlanFixtures.lifetime, PlanFixtures.monthly, PlanFixtures.yearly], featured: "app.midgar.test.gone")

        #expect(catalog.preselectedID == PlanFixtures.monthly)
    }

    @Test func aStoreWithOnlyAOneTimeProductPreselectsIt() {
        let catalog = PlanFixtures.catalog(products: [PlanFixtures.lifetimeProduct], terms: [], presentations: [:], order: [PlanFixtures.lifetime])

        #expect(catalog.preselectedID == PlanFixtures.lifetime)
    }

    @Test func anEmptyCatalogSelectsNothing() {
        var selection = MidgarPlanSelection()
        selection.reconcile(with: .empty)

        let changed = selection.select(PlanFixtures.yearly, in: .empty, isBusy: false)

        #expect(selection.selectedID == nil)
        #expect(!changed)
    }

    @Test func theFirstLoadSelectsThePreselectionAndAChoiceSurvivesAReload() {
        let catalog = PlanFixtures.catalog()
        var selection = MidgarPlanSelection()
        selection.reconcile(with: catalog)
        #expect(selection.selectedID == PlanFixtures.yearly)

        let changed = selection.select(PlanFixtures.lifetime, in: catalog, isBusy: false)
        #expect(changed)
        selection.reconcile(with: PlanFixtures.catalog(presentations: [:]))

        #expect(selection.selectedID == PlanFixtures.lifetime)
    }

    @Test func aChoiceThatIsNoLongerSoldFallsBackToThePreselection() {
        var selection = MidgarPlanSelection()
        selection.reconcile(with: PlanFixtures.catalog())
        selection.select(PlanFixtures.lifetime, in: PlanFixtures.catalog(), isBusy: false)

        selection.reconcile(with: PlanFixtures.catalog(products: [PlanFixtures.yearlyProduct, PlanFixtures.monthlyProduct]))

        #expect(selection.selectedID == PlanFixtures.yearly)
    }

    @Test func nothingCanBeSelectedWhileAPurchaseOrRestoreRunsOrForAPlanThatIsNotSold() {
        let catalog = PlanFixtures.catalog()
        var selection = MidgarPlanSelection()
        selection.reconcile(with: catalog)

        let whileBusy = selection.select(PlanFixtures.monthly, in: catalog, isBusy: true)
        let notSold = selection.select("app.midgar.test.gone", in: catalog, isBusy: false)

        #expect(!whileBusy)
        #expect(!notSold)
        #expect(selection.selectedID == PlanFixtures.yearly)
    }
}

@Suite struct PaywallArrangementTests {
    @Test func aNarrowWindowGetsOneColumnAndAWideOneGetsTwo() {
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 375) == .single)
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 430) == .single)
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 699) == .single)
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 700) == .twoColumns)
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 834) == .twoColumns)
        #expect(MidgarPaywallArrangement.arrangement(forWidth: 1920) == .twoColumns)
    }
}
