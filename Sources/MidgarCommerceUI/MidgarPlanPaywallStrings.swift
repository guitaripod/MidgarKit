import Foundation

/// The strings of the plan picker paywall, looked up in the package's own string catalog.
extension MidgarCommerceUIStrings {
    static func saveBadge(_ percent: String) -> String {
        String(localized: "Save \(percent)", bundle: .module, comment: "Badge on a plan card; the placeholder is the localized percentage saved against paying monthly, e.g. 44%")
    }

    static func perMonthBilledYearly(_ price: String) -> String {
        String(localized: "Just \(price) a month, billed yearly", bundle: .module, comment: "Detail on the yearly plan card; the placeholder is the localized per-month equivalent price")
    }

    static func perMonth(_ price: String) -> String {
        String(localized: "Just \(price) a month", bundle: .module, comment: "Detail on a plan card longer than a month; the placeholder is the localized per-month equivalent price")
    }

    static func cancelAnytime(_ renewal: String) -> String {
        String(localized: "\(renewal) · cancel anytime", bundle: .module, comment: "Detail on a subscription plan card without a trial; the placeholder is the price with its period, e.g. $4.99/month")
    }

    static var payOnceKeepForever: String {
        String(localized: "Pay once. Keep it forever.", bundle: .module, comment: "Detail on the one-time purchase plan card")
    }

    static var familySharingIncluded: String {
        String(localized: "Family Sharing included", bundle: .module, comment: "Detail on a plan card for a product the customer can share with their family")
    }

    static func lifetimeAnchor(years: String, annualName: String, total: String, lifetimeName: String, lifetimePrice: String) -> String {
        String(
            localized: "\(years) years of \(annualName) costs \(total). \(lifetimeName) is \(lifetimePrice) and never renews.",
            bundle: .module,
            comment: "Line under the plan cards comparing the yearly plan with the one-time purchase; placeholders: number of years, yearly plan name, what those years cost, one-time plan name, its price"
        )
    }

    static func oneTimeOffer(_ price: String) -> String {
        String(localized: "One-time purchase of \(price). No renewal.", bundle: .module, comment: "Line above the purchase button when a one-time purchase is selected; the placeholder is its price")
    }

    static var continueButton: String {
        String(localized: "Continue", bundle: .module, comment: "Purchase button of the paywall when the selected plan has no free trial")
    }

    static func tryFree(_ offer: String) -> String {
        String(localized: "Try \(offer)", bundle: .module, comment: "Purchase button of the paywall when the selected plan has a free trial; the placeholder is the offer, e.g. 1 week free")
    }

    static var timelineHeader: String {
        String(localized: "How your free trial works", bundle: .module, comment: "Header of the free trial timeline")
    }

    static var timelineToday: String {
        String(localized: "Today", bundle: .module, comment: "Free trial timeline: the first step, the day the trial starts")
    }

    static var timelineTodayDetail: String {
        String(localized: "Everything unlocks, free.", bundle: .module, comment: "Free trial timeline: what happens on the day the trial starts")
    }

    static var timelineReminderDetail: String {
        String(localized: "We'll remind you that your trial is ending.", bundle: .module, comment: "Free trial timeline: the step on which the app sends a reminder")
    }

    static func timelineChargeDetail(_ renewal: String) -> String {
        String(
            localized: "Your plan continues at \(renewal). Cancel before this day and you won't be charged.",
            bundle: .module,
            comment: "Free trial timeline: the day billing starts; the placeholder is the price with its period, e.g. $39.99/year"
        )
    }

    static var plansUnavailableTitle: String {
        String(localized: "Plans unavailable", bundle: .module, comment: "Title shown on the paywall when the App Store returned no plans")
    }

    static var plansUnavailableDetail: String {
        String(localized: "The App Store did not return any plans. Check your connection and try again.", bundle: .module, comment: "Detail shown on the paywall when the App Store returned no plans")
    }

    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "Button that loads the plans of the paywall again")
    }

    static var loadingPlans: String {
        String(localized: "Loading plans", bundle: .module, comment: "Accessibility label of the spinner while the plans of the paywall load")
    }

    static var purchasing: String {
        String(localized: "Purchasing", bundle: .module, comment: "Accessibility label of the spinner on the purchase button while a purchase runs")
    }
}
