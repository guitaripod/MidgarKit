import Foundation

/// Every string MidgarUI shows to people, looked up in the package's own string catalog.
enum MidgarUIStrings {
    static var settings: String {
        String(localized: "Settings", bundle: .module, comment: "Title of the settings screen")
    }

    static var restorePurchases: String {
        String(localized: "Restore Purchases", bundle: .module, comment: "Settings row that restores earlier App Store purchases")
    }

    static var purchasesRestored: String {
        String(localized: "Purchases restored", bundle: .module, comment: "Toast shown after restoring purchases finished")
    }

    static var support: String {
        String(localized: "Support", bundle: .module, comment: "Settings row that shows the support email address")
    }

    static var addressCopied: String {
        String(localized: "Address copied", bundle: .module, comment: "Toast shown after the support email address was copied")
    }

    static var copyAddress: String {
        String(localized: "Copy Address", bundle: .module, comment: "Context menu item that copies the support email address")
    }

    static var sendEmail: String {
        String(localized: "Send Email", bundle: .module, comment: "Context menu item that opens a new email to support")
    }

    static var privacyPolicy: String {
        String(localized: "Privacy Policy", bundle: .module, comment: "Settings row that opens the privacy policy")
    }

    static var termsOfUse: String {
        String(localized: "Terms of Use", bundle: .module, comment: "Settings row that opens the terms of use")
    }

    static var version: String {
        String(localized: "Version", bundle: .module, comment: "Settings row that shows the app version and build")
    }

    static var versionCopied: String {
        String(localized: "Version copied", bundle: .module, comment: "Toast shown after the app version was copied")
    }

    static var deleteAccount: String {
        String(localized: "Delete Account", bundle: .module, comment: "Settings row that deletes the person's account")
    }

    static var deleteAccountTitle: String {
        String(localized: "Delete your account?", bundle: .module, comment: "Title of the confirmation before deleting the account")
    }

    static var deleteAccountMessage: String {
        String(
            localized: "This permanently deletes your account and its data. This cannot be undone.",
            bundle: .module,
            comment: "Message of the confirmation before deleting the account"
        )
    }

    static var cancel: String {
        String(localized: "Cancel", bundle: .module, comment: "Button that dismisses a confirmation without doing anything")
    }

    static var copied: String {
        String(localized: "Copied", bundle: .module, comment: "Toast shown after text was copied to the clipboard")
    }

    static var failureTitle: String {
        String(localized: "Something went wrong", bundle: .module, comment: "Title of the alert shown when an action failed")
    }

    static var ok: String {
        String(localized: "OK", bundle: .module, comment: "Button that dismisses an alert")
    }

    static var linkFailed: String {
        String(localized: "The link could not be opened.", bundle: .module, comment: "Alert message when a link cannot be opened")
    }

    static var continueButton: String {
        String(localized: "Continue", bundle: .module, comment: "Button that goes to the next onboarding page or closes What's New")
    }

    static var getStarted: String {
        String(localized: "Get Started", bundle: .module, comment: "Button on the last onboarding page")
    }

    static var skip: String {
        String(localized: "Skip", bundle: .module, comment: "Button that skips the rest of onboarding")
    }

    static func pageOf(_ page: Int, _ total: Int) -> String {
        String(
            localized: "Page \(page) of \(total)",
            bundle: .module,
            comment: "Accessibility value of the onboarding page indicator"
        )
    }

    static var whatsNew: String {
        String(localized: "What's New", bundle: .module, comment: "Title of the sheet that lists the changes of the new app version")
    }
}
