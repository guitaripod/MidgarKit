import Foundation
import MidgarCommerce

/// The arithmetic behind the comparison captions of a plan picker. Every figure comes from StoreKit prices (`StoreProduct.price`), never from a constant, so a price change in App Store Connect or another storefront currency can never leave a caption quoting a stale number.
enum MidgarPlanCaptions {
    /// The price spread over `months`, in cents, or nil when either is not positive.
    static func monthlyEquivalent(price: Decimal, months: Int) -> Decimal? {
        guard price > 0, months > 0 else {
            return nil
        }
        return rounded(price / Decimal(months), scale: 2)
    }

    /// How much cheaper a plan of `months` months is per month than the monthly plan, as a whole percent, or nil when the plan saves nothing, a price is missing, or the plan is not longer than a month.
    static func savingsPercent(price: Decimal, months: Int, monthlyPrice: Decimal) -> Int? {
        guard months > 1, monthlyPrice > 0, let equivalent = monthlyEquivalent(price: price, months: months) else {
            return nil
        }
        let saved = (monthlyPrice - equivalent) / monthlyPrice * 100
        let percent = NSDecimalNumber(decimal: rounded(saved, scale: 0)).intValue
        return percent > 0 ? percent : nil
    }

    /// How many years of the annual plan cost what the lifetime product costs once, rounded down to a whole half year so the caption always understates what the subscription would cost. Nil when a price is missing or the lifetime price is under one and a half annual prices, where the comparison would not persuade anyone.
    static func lifetimeYears(lifetimePrice: Decimal, annualPrice: Decimal) -> Decimal? {
        guard lifetimePrice > 0, annualPrice > 0 else {
            return nil
        }
        let halves = NSDecimalNumber(decimal: rounded(lifetimePrice / annualPrice * 2, scale: 0, mode: .down)).intValue
        guard halves >= 3 else {
            return nil
        }
        return Decimal(halves) / 2
    }

    /// `amount` in the product's currency and the customer's locale, or nil when the product carries no currency code.
    static func format(_ amount: Decimal, currencyCode: String?, locale: Locale) -> String? {
        guard let currencyCode else {
            return nil
        }
        return amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// `44` as the localized `44%`, so copy never embeds a percent sign some locales write on the other side of the number.
    static func formatPercent(_ percent: Int, locale: Locale) -> String {
        (Decimal(percent) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// `2.5` as the localized `2.5`, with no trailing zero for a whole number.
    static func formatYears(_ years: Decimal, locale: Locale) -> String {
        years.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }

    static func rounded(_ value: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, mode)
        return result
    }
}

extension MidgarBillingPeriod {
    /// The whole months this period covers, or nil for days and weeks, which do not compare with a monthly price.
    var wholeMonths: Int? {
        switch unit {
        case .month: return value
        case .year: return value * 12
        case .day, .week: return nil
        }
    }

    /// True for exactly one month.
    var isMonth: Bool {
        unit == .month && value == 1
    }

    /// True for exactly one year.
    var isYear: Bool {
        unit == .year && value == 1
    }
}
