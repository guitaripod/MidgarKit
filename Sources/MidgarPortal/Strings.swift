import Foundation

/// Every string the portal shows to people, looked up in the package's own string catalog.
enum MidgarStrings {
    static var close: String {
        String(localized: "Close", bundle: .module, comment: "Accessibility label of the button that closes the Midgar portal")
    }

    static func installedCount(_ owned: Int, of total: Int) -> String {
        String(
            localized: "You have \(owned) of \(total)",
            bundle: .module,
            comment: "Portal header subtitle: how many of the Midgar apps for this device are installed"
        )
    }

    static var coreBlurb: String {
        String(
            localized: "Every app we make lives here. Drag to explore, tap an icon to look closer.",
            bundle: .module,
            comment: "Portal card text while the Midgar emblem at the centre is selected"
        )
    }

    static var allApps: String {
        String(localized: "ALL APPS", bundle: .module, comment: "Button that opens the Midgar developer page in the App Store")
    }

    static var open: String {
        String(localized: "OPEN", bundle: .module, comment: "Button that opens an installed Midgar app")
    }

    static var view: String {
        String(localized: "VIEW", bundle: .module, comment: "Button that opens the App Store page of a Midgar app")
    }

    static var get: String {
        String(localized: "GET", bundle: .module, comment: "Button that installs a free Midgar app")
    }

    static func sendTo(_ device: String) -> String {
        String(
            localized: "SEND TO \(device)",
            bundle: .module,
            comment: "Button that shares an app link, %@ is a device such as Mac or Apple TV"
        )
    }

    static var youAreHere: String {
        String(localized: "You are here", bundle: .module, comment: "Label on the app the person is using right now")
    }

    static var installed: String {
        String(localized: "Installed", bundle: .module, comment: "Chip shown on a Midgar app that is already installed")
    }

    static var entryTitle: String {
        String(localized: "Midgar universe", bundle: .module, comment: "Title of the card in Settings that opens the portal")
    }

    static func entrySubtitle(appCount: Int) -> String {
        String(
            localized: "\(appCount) apps to explore",
            bundle: .module,
            comment: "Subtitle of the card in Settings that opens the portal"
        )
    }

    static var coreAccessibilityHint: String {
        String(localized: "All apps by Midgar Oy", bundle: .module, comment: "Accessibility hint of the Midgar emblem in the portal")
    }

    static var yourMidgar: String {
        String(localized: "Your Midgar", bundle: .module, comment: "Title of the panel that lists the Midgar apps the person has and what they own in each, and the button that opens it")
    }

    static var yourApps: String {
        String(localized: "Your apps", bundle: .module, comment: "Heading above the Midgar apps the person already has")
    }

    static var moreFromMidgar: String {
        String(localized: "More from Midgar", bundle: .module, comment: "Heading above Midgar apps the person does not have yet")
    }

    static var lifetime: String {
        String(localized: "Lifetime", bundle: .module, comment: "Shown under an unlock the person bought once and keeps for good")
    }

    static var unlocked: String {
        String(localized: "Unlocked", bundle: .module, comment: "Name of a purchase that has no entitlement name, such as a one-time unlock")
    }

    static func activeUntil(_ date: String) -> String {
        String(
            localized: "Active until \(date)",
            bundle: .module,
            comment: "Shown under a subscription: the date its paid period ends, %@ is a date"
        )
    }

    static func billingIssue(until date: String) -> String {
        String(
            localized: "Billing issue, active until \(date)",
            bundle: .module,
            comment: "Shown under a subscription whose renewal payment failed and that stays active during the grace period, %@ is a date"
        )
    }
}
