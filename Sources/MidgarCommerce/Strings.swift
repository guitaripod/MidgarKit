import Foundation

/// Every string MidgarCommerce produces for people, looked up in the package's own string catalog under stable keys.
enum MidgarCommerceStrings {
    static func freeThenRecurring(_ duration: String, _ recurring: String, locale: Locale) -> String {
        String(
            localized: "trial.freeThenRecurring",
            defaultValue: "\(duration) free, then \(recurring)",
            bundle: .module,
            locale: locale,
            comment: "Summary of a free trial. First is the trial length, e.g. 1 week; second is the renewal price with its period, e.g. $39.99/year"
        )
    }

    static func introThenRecurring(_ introPrice: String, _ duration: String, _ recurring: String, locale: Locale) -> String {
        String(
            localized: "trial.introThenRecurring",
            defaultValue: "\(introPrice) for \(duration), then \(recurring)",
            bundle: .module,
            locale: locale,
            comment: "Summary of a paid introductory offer. First is the offer price, e.g. $0.99 or $0.99/month; second is how long it lasts, e.g. 3 months; third is the renewal price with its period, e.g. $4.99/month"
        )
    }

    static func trialBadge(_ duration: String, locale: Locale) -> String {
        String(
            localized: "trial.badge",
            defaultValue: "\(duration) free",
            bundle: .module,
            locale: locale,
            comment: "Short badge on a plan that starts with a free trial. The placeholder is the trial length, e.g. 1 week"
        )
    }

    static func pricePerUnit(_ price: String, _ unit: String, locale: Locale) -> String {
        String(
            localized: "price.perUnit",
            defaultValue: "\(price)/\(unit)",
            bundle: .module,
            locale: locale,
            comment: "A price for one billing period. First is the price, e.g. $4.99; second is the period name, e.g. month"
        )
    }

    static func priceEvery(_ price: String, _ duration: String, locale: Locale) -> String {
        String(
            localized: "price.everyPeriod",
            defaultValue: "\(price) every \(duration)",
            bundle: .module,
            locale: locale,
            comment: "A price for a billing period longer than one unit. First is the price, e.g. $9.99; second is the length, e.g. 3 months"
        )
    }

    static func unitName(_ unit: MidgarPeriodUnit, locale: Locale) -> String {
        switch unit {
        case .day:
            return String(localized: "unit.day", defaultValue: "day", bundle: .module, locale: locale, comment: "Singular name of a billing period after a price, as in $0.99/day")
        case .week:
            return String(localized: "unit.week", defaultValue: "week", bundle: .module, locale: locale, comment: "Singular name of a billing period after a price, as in $1.99/week")
        case .month:
            return String(localized: "unit.month", defaultValue: "month", bundle: .module, locale: locale, comment: "Singular name of a billing period after a price, as in $4.99/month")
        case .year:
            return String(localized: "unit.year", defaultValue: "year", bundle: .module, locale: locale, comment: "Singular name of a billing period after a price, as in $39.99/year")
        }
    }
}
