import Foundation

/// Every string MidgarCommerceUI shows to people, looked up in the package's own string catalog.
enum MidgarCommerceUIStrings {
    static var restorePurchases: String {
        String(localized: "Restore Purchases", bundle: .module, comment: "Button on the paywall that restores earlier App Store purchases")
    }

    static var termsOfUse: String {
        String(localized: "Terms of Use", bundle: .module, comment: "Link on the paywall to the terms of use")
    }

    static var privacyPolicy: String {
        String(localized: "Privacy Policy", bundle: .module, comment: "Link on the paywall to the privacy policy")
    }

    static var autoRenewTerms: String {
        String(
            localized: "Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in your Apple Account settings.",
            bundle: .module,
            comment: "Required disclosure under the subscription options of the paywall"
        )
    }

    static var purchasesRestored: String {
        String(localized: "Purchases restored", bundle: .module, comment: "Toast shown after restoring purchases found something to restore")
    }

    static var nothingToRestore: String {
        String(localized: "No purchases to restore", bundle: .module, comment: "Toast shown after restoring purchases found nothing")
    }

    static var restoring: String {
        String(localized: "Restoring purchases", bundle: .module, comment: "Accessibility label of the spinner while purchases are being restored")
    }

    static var restoreFailed: String {
        String(localized: "Purchases could not be restored. Please try again.", bundle: .module, comment: "Alert message when restoring purchases failed")
    }

    static var purchaseFailed: String {
        String(localized: "The purchase could not be completed. Please try again.", bundle: .module, comment: "Alert message when a purchase failed")
    }

    static var purchaseUnverified: String {
        String(
            localized: "The App Store could not verify this purchase, so it was not applied. Please try again.",
            bundle: .module,
            comment: "Alert message when the signature of a purchase could not be verified"
        )
    }

    static var purchasePending: String {
        String(
            localized: "Waiting for approval. You will get access as soon as it is approved.",
            bundle: .module,
            comment: "Toast shown when a purchase needs approval, for example Ask to Buy"
        )
    }

    static var purchased: String {
        String(localized: "Purchased", bundle: .module, comment: "Label on a plan card for a product the customer already owns")
    }

    static var failureTitle: String {
        String(localized: "Something went wrong", bundle: .module, comment: "Title of the alert shown when a purchase or restore failed")
    }

    static var ok: String {
        String(localized: "OK", bundle: .module, comment: "Button that dismisses an alert")
    }

    static var close: String {
        String(localized: "Close", bundle: .module, comment: "Button that closes the paywall")
    }

    static var productsUnavailable: String {
        String(localized: "Purchases are not available right now.", bundle: .module, comment: "Shown on the paywall when no product could be loaded")
    }
}
