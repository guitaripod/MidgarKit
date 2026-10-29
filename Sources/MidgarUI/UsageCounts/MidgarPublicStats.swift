import Foundation

/// The part of Midgar's public numbers (`GET https://api.midgarcorp.cc/v1/ops/public/stats`) that an app's Usage Counts screen shows: the finished weeks of each app. The server has already hidden every count under its minimum as the string `"<10"`; this type hides one again if a smaller figure ever reached the device.
struct MidgarPublicStats: Decodable, Sendable, Equatable {
    /// The smallest figure the server shows when its answer does not say.
    static let defaultMinimumCount = 10

    /// A figure of the public numbers: the count, or "fewer than N" where the server hid it.
    enum Count: Sendable, Equatable {
        case exactly(Int)
        case fewerThan(Int)
    }

    /// One finished ISO week of one app. A figure that is missing or in a shape this version does not know is nil.
    struct Week: Decodable, Sendable, Equatable {
        /// The Monday the week starts on, `YYYY-MM-DD`.
        let period: String
        let weeklyActiveInstalls: Count?
        let newInstalls: Count?

        init(period: String, weeklyActiveInstalls: Count? = nil, newInstalls: Count? = nil) {
            self.period = period
            self.weeklyActiveInstalls = weeklyActiveInstalls
            self.newInstalls = newInstalls
        }

        private enum CodingKeys: String, CodingKey {
            case period
            case weeklyActiveInstalls = "wau"
            case newInstalls = "new_installs"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            period = try container.decode(String.self, forKey: .period)
            weeklyActiveInstalls = try? container.decode(Count.self, forKey: .weeklyActiveInstalls)
            newInstalls = try? container.decode(Count.self, forKey: .newInstalls)
        }
    }

    struct App: Decodable, Sendable, Equatable {
        let weeks: [Week]
    }

    private struct Rules: Decodable {
        let minimumCount: Int?

        private enum CodingKeys: String, CodingKey {
            case minimumCount = "min_count"
        }
    }

    /// Apps by registry slug. An app whose entry this version cannot read is left out, so it cannot take the others down with it.
    let apps: [String: App]
    /// The smallest figure the server publishes; anything below it is shown as "fewer than" this.
    let minimumCount: Int

    init(apps: [String: App], minimumCount: Int = MidgarPublicStats.defaultMinimumCount) {
        self.apps = apps
        self.minimumCount = minimumCount
    }

    private enum CodingKeys: String, CodingKey {
        case apps
        case rules
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([String: Lossy<App>].self, forKey: .apps)
        apps = entries.compactMapValues(\.value)
        let minimum = (try? container.decode(Rules.self, forKey: .rules))?.minimumCount
        minimumCount = minimum.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultMinimumCount
    }

    /// The latest finished week of the app with this registry slug, or nil when the answer has nothing for it.
    func latestWeek(for appID: String) -> MidgarAppNumbers? {
        guard let week = apps[appID]?.weeks.max(by: { $0.period < $1.period }) else {
            return nil
        }
        let numbers = MidgarAppNumbers(
            weekStarting: week.period,
            weeklyActiveInstalls: week.weeklyActiveInstalls.map(shown),
            newInstalls: week.newInstalls.map(shown)
        )
        return numbers.isEmpty ? nil : numbers
    }

    /// The figure as it may be shown: a count under the minimum becomes "fewer than" the minimum.
    private func shown(_ count: Count) -> Count {
        switch count {
        case .exactly(let value) where value < minimumCount: .fewerThan(minimumCount)
        case .exactly, .fewerThan: count
        }
    }
}

extension MidgarPublicStats.Count: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let whole = try? container.decode(Int.self), whole >= 0 {
            self = .exactly(whole)
        } else if let number = try? container.decode(Double.self), number.isFinite, number >= 0 {
            self = .exactly(Int(number.rounded()))
        } else if let hidden = Self.hiddenThreshold(try container.decode(String.self)) {
            self = .fewerThan(hidden)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a count")
        }
    }

    /// The N of `"<N>"`, or nil for any other text.
    private static func hiddenThreshold(_ text: String) -> Int? {
        guard text.hasPrefix("<"), let threshold = Int(text.dropFirst()), threshold > 0 else {
            return nil
        }
        return threshold
    }
}

/// An app's figures for one finished week, ready to show.
struct MidgarAppNumbers: Sendable, Equatable {
    /// The Monday the week starts on, `YYYY-MM-DD`.
    let weekStarting: String
    let weeklyActiveInstalls: MidgarPublicStats.Count?
    let newInstalls: MidgarPublicStats.Count?

    /// True when the week has no figure to show.
    var isEmpty: Bool {
        weeklyActiveInstalls == nil && newInstalls == nil
    }

    /// The week's first day for display, in the person's language. The period is a UTC date, so it is formatted in UTC and never slips a day. The period itself when it is not a date.
    var weekStartingDisplay: String {
        guard let date = Self.date(from: weekStarting) else {
            return weekStarting
        }
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc))
    }

    /// Midnight UTC of a `YYYY-MM-DD` date, or nil.
    static func date(from period: String) -> Date? {
        let parts = period.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension MidgarPublicStats.Count {
    /// The figure in the person's language: a grouped number, or "fewer than 10".
    var display: String {
        switch self {
        case .exactly(let value): value.formatted(.number)
        case .fewerThan(let threshold): MidgarUIStrings.fewerThan(threshold)
        }
    }
}

/// Decodes to nil instead of throwing, so one unreadable entry of a collection does not fail the rest.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? decoder.singleValueContainer().decode(Value.self)
    }
}
