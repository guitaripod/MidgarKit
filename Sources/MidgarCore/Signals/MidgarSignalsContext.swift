import Foundation

/// What an install remembers about itself so MidgarKit can do the joining on the device: whether it pays, how often it showed a purchase screen and from where last, the days it was active, whether the app's value moment was reached, and the stories waiting to be sent. None of it leaves the device as it is. It only decides which value of a closed set an event carries, which is why no event needs an identifier to be read beside another.
struct MidgarSignalsContext: Codable, Sendable, Equatable {
    /// A story kept back, so that when it arrives says nothing about when it happened.
    struct Held: Codable, Sendable, Equatable {
        let event: MidgarSignalEvent
        let releaseAt: Date
    }

    /// The active days kept, which is the window `renewal.off` looks back over.
    static let activeDayWindow = 14
    /// Stories kept at most; an install that makes more in two days loses the oldest.
    static let maximumHeld = 20
    /// Purchase screens counted at most, far past the last bucket.
    static let maximumViews = 1_000

    var tier = MidgarSignal.Tier.unknown.rawValue
    var paywallViews = 0
    var lastPlacement: String?
    /// Days since 1970 on which the app was active, oldest first.
    var activeDays: [Int] = []
    var reachedValue = false
    var held: [Held] = []

    /// The day number of a date, the unit `activeDays` counts in.
    static func day(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// Adds the day of `date` and forgets the days that left the window. Returns whether anything changed.
    mutating func markActive(at date: Date) -> Bool {
        let today = Self.day(of: date)
        let kept = activeDays.filter { $0 > today - Self.activeDayWindow && $0 < today } + [today]
        guard kept != activeDays else {
            return false
        }
        activeDays = kept
        return true
    }

    /// On how many of the fourteen days up to `date` the app was active.
    func activeDayCount(at date: Date) -> Int {
        let today = Self.day(of: date)
        return activeDays.filter { $0 > today - Self.activeDayWindow && $0 <= today }.count
    }

    /// Counts one purchase screen and remembers where it was opened from.
    mutating func countPaywall(placement: String) {
        paywallViews = min(paywallViews + 1, Self.maximumViews)
        lastPlacement = placement
    }

    /// Keeps a story until `releaseAt`, dropping the oldest when too many wait.
    mutating func hold(_ event: MidgarSignalEvent, until releaseAt: Date) {
        held.append(Held(event: event, releaseAt: releaseAt))
        if held.count > Self.maximumHeld {
            held.removeFirst(held.count - Self.maximumHeld)
        }
    }

    /// Takes out the stories whose wait is over at `date`, oldest first.
    mutating func releaseDue(at date: Date) -> [MidgarSignalEvent] {
        let due = held.filter { $0.releaseAt <= date }
        guard !due.isEmpty else {
            return []
        }
        held.removeAll { $0.releaseAt <= date }
        return due.map(\.event)
    }
}

/// The buckets context and stories are sent in. Each turns something exact that only the device knows into one of a handful of words.
enum MidgarSignalsBuckets {
    /// How long ago the app was installed: the first 24 hours, the rest of the first week, of the first four weeks, of the first ninety days, or longer. Unknown when the device cannot tell or the date is a placeholder.
    static func age(installedAt: Date?, now: Date) -> MidgarSignal.Age {
        guard let installedAt, installedAt >= MidgarSignalsInstallDate.earliestPlausible else {
            return .unknown
        }
        switch Int(max(0, now.timeIntervalSince(installedAt)) / 86_400) {
        case 0: return .day0
        case 1...6: return .week1
        case 7...27: return .month1
        case 28...89: return .quarter1
        default: return .older
        }
    }

    /// How soon the value moment came: in the run that first kept context for an install made within the day, later that day, within the week, or after.
    static func within(age: MidgarSignal.Age, isFirstRun: Bool) -> MidgarSignal.ValueFirstWithin {
        switch age {
        case .day0: return isFirstRun ? .firstSession : .day0
        case .week1: return .week1
        case .month1, .quarter1, .older, .unknown: return .later
        }
    }

    /// How many purchase screens the install had shown when it bought, the one it bought from included.
    static func views(_ count: Int) -> MidgarSignal.PurchaseStoryViewsBefore {
        switch count {
        case ...0: return .none
        case 1: return .one
        case 2...3: return .twoThree
        case 4...9: return .fourNine
        default: return .tenPlus
        }
    }

    /// How long a subscription had run when its renewal was turned off.
    static func tenure(startedAt: Date, now: Date) -> MidgarSignal.RenewalOffTenure {
        switch Int(max(0, now.timeIntervalSince(startedAt)) / 86_400) {
        case ..<30: return .firstMonth
        case ..<90: return .quarter1
        case ..<180: return .half1
        case ..<365: return .year1
        default: return .longer
        }
    }

    /// On how many of the last fourteen days the app was opened.
    static func activeDays(_ count: Int) -> MidgarSignal.RenewalOffActiveDays {
        switch count {
        case ...0: return .none
        case 1...2: return .oneTwo
        case 3...6: return .threeSix
        default: return .sevenPlus
        }
    }
}

/// The context on disk, `<directory>/signals-context-<app>.json`, removed with the ledger when the person turns usage counts off.
struct MidgarSignalsContextStore: Sendable {
    let fileURL: URL

    init(store: MidgarSignalsStore) {
        fileURL = store.sibling("context")
    }

    func load() -> MidgarSignalsContext? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(MidgarSignalsContext.self, from: data)
    }

    func save(_ context: MidgarSignalsContext) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(context).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
