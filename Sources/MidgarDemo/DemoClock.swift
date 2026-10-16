import Foundation

/// The clock screenshot-visible code reads instead of `Date()`. It is frozen while a demo world is active
/// and the system clock otherwise, so one call site serves both the app and its screenshot runs.
public enum DemoClock {
    /// The frozen demo date while a demo world is active, otherwise the current date.
    public static var now: Date {
        DemoClockStore.shared.frozenDate ?? Date()
    }
}

/// Holds the frozen date `DemoClock` reads. `DemoRegistry.activate` is the only writer.
/// Unchecked because `frozen` is read and written only while `lock` is held, which makes the type safe to share.
final class DemoClockStore: @unchecked Sendable {
    static let shared = DemoClockStore()

    private let lock = NSLock()
    private var frozen: Date?

    private init() {}

    var frozenDate: Date? {
        lock.withLock { frozen }
    }

    func freeze(_ date: Date?) {
        lock.withLock { frozen = date }
    }
}
