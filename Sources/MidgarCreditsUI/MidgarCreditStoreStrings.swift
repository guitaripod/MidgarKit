import Foundation

/// Every string MidgarCreditsUI shows to people, looked up in the target's own string catalog. Counts of credits take the plural form of the language.
enum MidgarCreditsUIStrings {
    static var purchaseFailed: String {
        String(localized: "The purchase could not be completed. Please try again.", bundle: .module, comment: "Alert message when a purchase failed")
    }

    static var tryAgain: String {
        String(localized: "Try again", bundle: .module, comment: "Button that loads the credit packs again")
    }

    static var purchasing: String {
        String(localized: "Purchasing", bundle: .module, comment: "Accessibility label of the spinner on the buy button while a purchase runs")
    }

    static var creditsBalanceTitle: String {
        String(localized: "Your balance", bundle: .module, comment: "Label above the number of credits the person has in the credit store")
    }

    static func creditsCount(_ count: Int) -> String {
        String(localized: "\(count) credits", bundle: .module, comment: "A number of credits, which takes the plural form of the language; the placeholder is the count, e.g. 150 credits")
    }

    static var creditsBalanceUnavailable: String {
        String(localized: "Your balance could not be loaded.", bundle: .module, comment: "Shown in the credit store when the balance could not be read")
    }

    static var creditsAllowancesTitle: String {
        String(localized: "Free allowances", bundle: .module, comment: "Header of the list of free allowances that renew, in the credit store")
    }

    static func creditsAllowanceLeft(remaining: Int, limit: Int) -> String {
        String(localized: "\(remaining) of \(limit) left", bundle: .module, comment: "How much of a free allowance is left; placeholders: what is left, the whole allowance, e.g. 2 of 3 left")
    }

    static func creditsAllowanceResets(_ date: String) -> String {
        String(localized: "Resets \(date)", bundle: .module, comment: "When a free allowance refills; the placeholder is a short date, e.g. Oct 12")
    }

    static func creditsShortfall(_ count: Int) -> String {
        String(localized: "You need \(count) more credits to continue.", bundle: .module, comment: "Banner at the top of the credit store when an action needs more credits than the person has; the placeholder is how many more, which takes the plural form of the language")
    }

    static var creditsCoversShortfall: String {
        String(localized: "Enough for this", bundle: .module, comment: "Badge on the smallest credit pack that covers what the person is missing")
    }

    static func creditsBuy(_ price: String) -> String {
        String(localized: "Buy for \(price)", bundle: .module, comment: "Accessibility label of the button that buys a credit pack; the placeholder is its price")
    }

    static var creditsLoadingPacks: String {
        String(localized: "Loading credit packs", bundle: .module, comment: "Accessibility label of the spinner while the credit packs load")
    }

    static var creditsPacksUnavailableTitle: String {
        String(localized: "Credit packs unavailable", bundle: .module, comment: "Title shown in the credit store when the App Store returned no credit packs")
    }

    static var creditsPacksUnavailableDetail: String {
        String(localized: "The App Store did not return any credit packs. Check your connection and try again.", bundle: .module, comment: "Detail shown in the credit store when the App Store returned no credit packs")
    }

    static var creditsConfirmingTitle: String {
        String(localized: "Your purchase is being confirmed", bundle: .module, comment: "Title of the row shown after a credit pack was paid for but its credits have not arrived yet")
    }

    static var creditsConfirmingDetail: String {
        String(localized: "Your credits arrive as soon as it is confirmed. You do not need to buy again.", bundle: .module, comment: "Detail of the row shown after a credit pack was paid for but its credits have not arrived yet")
    }

    static func creditsAdded(_ count: Int) -> String {
        String(localized: "\(count) credits added", bundle: .module, comment: "Message after a credit pack was credited; the placeholder is how many credits arrived, which takes the plural form of the language")
    }

    static var creditsAwaitingApproval: String {
        String(localized: "Waiting for approval. Your credits arrive as soon as it is approved.", bundle: .module, comment: "Message after a credit pack purchase needs approval, for example Ask to Buy")
    }

    static var creditsOffline: String {
        String(localized: "You are offline. Check your connection and try again.", bundle: .module, comment: "Message when a credit purchase could not reach the server because the device is offline")
    }

    static var creditsWalletUnavailable: String {
        String(localized: "Credits are unavailable right now. Nothing was charged.", bundle: .module, comment: "Message when the credit wallet cannot be reached during a credit purchase")
    }

    static var creditsSignIn: String {
        String(localized: "Your session has expired. Sign in and try again.", bundle: .module, comment: "Message when a credit purchase was refused because the person is not signed in")
    }

    static var creditsRateLimited: String {
        String(localized: "Too many requests. Try again in a moment.", bundle: .module, comment: "Message when the credit service asks the app to slow down")
    }

    static var creditsRejected: String {
        String(localized: "The purchase could not be verified. If you were charged, contact support.", bundle: .module, comment: "Message when the credit service refused to credit a pack the person paid for")
    }

    static var creditsPacksNotAvailable: String {
        String(localized: "Credit packs are not available right now.", bundle: .module, comment: "Message when the app has no credit pack it can sell")
    }
}
