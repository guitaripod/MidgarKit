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
    /// Records `app.active` once for every period (the device's calendar day, ISO week and month) this install has not
    /// reported yet, so the server's daily counts add up to daily, weekly and monthly active installs.
    /// ``configure(configuration:config:directory:appVersion:)`` calls it at launch and on every return to the
    /// foreground. Nothing is recorded or remembered while the kill switch is on.
    public func noteActive() {
        guard !isKilled else {
            return
        }
        let store = MidgarSignalsActivityStore(directory: activityDirectory, appID: activityAppID)
        let reported = store.load()
        var updated = reported
        let date = now()
        for period in MidgarActivePeriod.allCases {
            let key = Self.periodKey(period, at: date, calendar: Self.activityCalendar)
            guard reported[period.rawValue] != key else {
                continue
            }
            record("app.active", props: ["period": .string(period.rawValue)])
            updated[period.rawValue] = key
        }
        if updated != reported {
            store.save(updated)
        }
    }

    /// The ISO 8601 calendar in the device's time zone, so a day ends at the person's midnight and a week starts on Monday.
    static var activityCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    /// The name of the period `date` falls in: `2026-10-25`, `2026-W43` or `2026-10`.
    static func periodKey(_ period: MidgarActivePeriod, at date: Date, calendar: Calendar) -> String {
        switch period {
        case .day:
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        case .week:
            let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        }
    }
}

/// Which period of each kind this install last reported active, `<directory>/signals-activity-<app>.json`.
struct MidgarSignalsActivityStore: Sendable {
    let fileURL: URL

    init(directory: URL?, appID: String) {
        let queueFile = MidgarSignalsStore(directory: directory, appID: appID).fileURL
        fileURL = queueFile.deletingLastPathComponent()
            .appendingPathComponent(queueFile.lastPathComponent.replacingOccurrences(of: "signals-", with: "signals-activity-"))
    }

    /// The periods reported so far, or none when the file is missing or unreadable, in which case the current periods are reported again.
    func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let marks = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return marks
    }

    func save(_ marks: [String: String]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(marks).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

/// Calls back when the app returns to the foreground. The notification is named by its raw value so MidgarCore never
/// imports UIKit or AppKit. The only stored property is an immutable observer token that is only removed in `deinit`,
/// which is what makes the unchecked conformance sound.
final class MidgarForegroundObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(onForeground: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: Self.name, object: nil, queue: nil) { _ in
            onForeground()
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
}
