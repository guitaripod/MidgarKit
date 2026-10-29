import Foundation
import MidgarCore

extension MidgarUIStrings {
    static var usageCountsTitle: String {
        String(localized: "Usage Counts", bundle: .module, comment: "Title of the Usage Counts screen in an app's Settings, and the label of the Settings row that opens it")
    }

    static var usageCountsIntro: String {
        String(
            localized: "Usage counts are counts, not people. Nothing in them identifies your device or you, and small numbers are never shown.",
            bundle: .module,
            comment: "Short intro paragraph at the top of the Usage Counts screen, about anonymous analytics"
        )
    }

    static var usageCountsSwitchFooter: String {
        String(
            localized: "Turning this off stops the app from sending counts and deletes any that are waiting.",
            bundle: .module,
            comment: "Footer under the on/off switch for anonymous usage counts"
        )
    }

    static var whatThisAppSends: String {
        String(localized: "What this app sends", bundle: .module, comment: "Section header above the list of anonymous counts the app can send")
    }

    static var nothingIsSent: String {
        String(
            localized: "Counts are turned off, so none of these are sent.",
            bundle: .module,
            comment: "Footer under the list of counts while the switch is off"
        )
    }

    static var installWeekNote: String {
        String(
            localized: "Includes the week this app was installed",
            bundle: .module,
            comment: "Extra note on a count: it also says in which calendar week the app was installed, not the date"
        )
    }

    static var thisAppsNumbers: String {
        String(localized: "This app's numbers", bundle: .module, comment: "Section header above this app's public usage figures")
    }

    static var weeklyActiveInstalls: String {
        String(localized: "Weekly active installs", bundle: .module, comment: "Label of a public figure: how many installs were active in a week")
    }

    static var newInstalls: String {
        String(localized: "New installs", bundle: .module, comment: "Label of a public figure: how many new installs there were in a week")
    }

    static var allOfMidgarsNumbers: String {
        String(localized: "All of Midgar's numbers", bundle: .module, comment: "Link to a web page with all of Midgar's public usage figures")
    }

    /// A public figure that is too small to show, "fewer than 10".
    static func fewerThan(_ threshold: Int) -> String {
        String(localized: "fewer than \(threshold)", bundle: .module, comment: "Shown instead of a small public figure; the number is the smallest figure shown")
    }

    /// The footer under the public figures, naming the week they cover by the date it started.
    static func finishedWeek(starting date: String) -> String {
        String(
            localized: "Finished week starting \(date). These count installs, not people.",
            bundle: .module,
            comment: "Footer under the public figures; the placeholder is a date such as Oct 19, 2026"
        )
    }

    /// "On" or "Off", the value of the row that opens the Usage Counts screen.
    static func onOff(isEnabled: Bool) -> String {
        isEnabled
            ? String(localized: "On", bundle: .module, comment: "Value of a setting that is switched on")
            : String(localized: "Off", bundle: .module, comment: "Value of a setting that is switched off")
    }

    /// An event's purpose in the person's language. The registry's English sentence is the key, so an event whose purpose has no translation yet shows the English.
    static func purpose(of entry: MidgarSignalCatalog.Entry) -> String {
        Bundle.module.localizedString(forKey: entry.purpose, value: entry.purpose, table: nil)
    }

    /// How often one install may send an event, in words.
    static func frequency(of uniqueness: MidgarSignal.Uniqueness) -> String {
        switch uniqueness {
        case .each:
            String(localized: "Sent every time it happens", bundle: .module, comment: "How often a count can be sent: every time the thing happens")
        case .daily:
            String(localized: "Sent at most once a day", bundle: .module, comment: "How often a count can be sent")
        case .weekly:
            String(localized: "Sent at most once a week", bundle: .module, comment: "How often a count can be sent")
        case .monthly:
            String(localized: "Sent at most once a month", bundle: .module, comment: "How often a count can be sent")
        case .lifetime:
            String(localized: "Sent only the first time it happens", bundle: .module, comment: "How often a count can be sent: only the very first time, ever")
        case .perPeriod:
            String(
                localized: "Sent at most once a day, once a week and once a month",
                bundle: .module,
                comment: "How often a count can be sent: one count for each of the three periods"
            )
        }
    }
}
