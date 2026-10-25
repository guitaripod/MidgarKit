import Foundation

/// The calendar periods an install reports itself active in, once each. Summing one period's `app.active` counts over
/// the days of that period gives the distinct active installs of the period, with no identifier sent: an install sends
/// `week` on the first day it is active in a week and never again that week.
public enum MidgarActivePeriod: String, CaseIterable, Sendable {
    case day
    case week
    case month
}

extension MidgarSignals {
    /// Sends `app.active` for the day, week and month of the device's calendar. The uniqueness the registry gives the event keeps each period to one send per install, so the server's daily counts add up to daily, weekly and monthly active installs.
    /// ``configure(configuration:config:directory:appVersion:)`` calls it at launch and on every return to the
    /// foreground. Nothing is sent or remembered while the kill switch is on or usage counts are off.
    public func noteActive() {
        for period in MidgarSignal.Period.allCases {
            send(.appActive(period: period))
        }
    }
}

/// Calls back when the app returns to the foreground, or, given ``backgroundName``, when it leaves it. The notification is named by its raw value so MidgarCore never
/// imports UIKit or AppKit. The only stored property is an immutable observer token that is only removed in `deinit`,
/// which is what makes the unchecked conformance sound.
final class MidgarForegroundObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(name: Notification.Name = MidgarForegroundObserver.name, perform: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            perform()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }

    static var name: Notification.Name {
        #if os(macOS)
        Notification.Name("NSApplicationDidBecomeActiveNotification")
        #else
        Notification.Name("UIApplicationWillEnterForegroundNotification")
        #endif
    }

    static var backgroundName: Notification.Name {
        #if os(macOS)
        Notification.Name("NSApplicationDidResignActiveNotification")
        #else
        Notification.Name("UIApplicationDidEnterBackgroundNotification")
        #endif
    }
}
