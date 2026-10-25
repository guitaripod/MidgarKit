import Foundation

/// The names of the calendar periods the device is in at one moment: `2026-10-25`, `2026-W43` and `2026-10`.
struct MidgarSignalPeriodKeys: Sendable, Equatable {
    /// The span of time these names hold for. It ends at the next midnight, or a minute after `validFrom`, whichever comes first, so a changed time zone is picked up within a minute.
    let validFrom: Date
    let validUntil: Date
    let day: String
    let week: String
    let month: String

    /// The names for `date` in the device's ISO calendar.
    init(at date: Date, calendar: Calendar = MidgarSignals.activityCalendar) {
        validFrom = date
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(60)
        validUntil = min(midnight, date.addingTimeInterval(Self.lifetime))
        day = MidgarSignals.periodKey(.day, at: date, calendar: calendar)
        week = MidgarSignals.periodKey(.week, at: date, calendar: calendar)
        month = MidgarSignals.periodKey(.month, at: date, calendar: calendar)
    }

    static let lifetime: TimeInterval = 60

    func contains(_ date: Date) -> Bool {
        date >= validFrom && date < validUntil
    }

    func key(for period: MidgarActivePeriod) -> String {
        switch period {
        case .day: return day
        case .week: return week
        case .month: return month
        }
    }

    /// Whether `mark` is the current period of any kind, which is what keeps a ledger entry alive.
    func isCurrent(_ mark: String) -> Bool {
        mark == day || mark == week || mark == month
    }
}

extension MidgarSignals {
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
