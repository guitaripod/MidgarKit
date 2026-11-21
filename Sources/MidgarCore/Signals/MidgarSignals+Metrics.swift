import Foundation

/// The numbers of one daily MetricKit metrics payload, read into plain values. A value MetricKit did not report is nil and is left out of the event.
public protocol MidgarMetricPayload: Sendable {
    /// Median time to first draw of a cold launch, in milliseconds.
    var coldLaunchMedianMilliseconds: Double? { get }
    /// Seconds spent hanging per hour in the foreground.
    var hangSecondsPerHour: Double? { get }
    var cumulativeForegroundSeconds: Double? { get }
    var peakMemoryMegabytes: Double? { get }
    /// How often the system ended the app during the payload's day, by reason, where the platform reports it.
    var exits: MidgarExitCounts? { get }
}

extension MidgarMetricPayload {
    public var exits: MidgarExitCounts? {
        nil
    }
}

/// How often the system ended the app in one day: in the foreground for memory, for not responding (the watchdog) and after a fault, and in the background for memory.
public struct MidgarExitCounts: Sendable, Equatable {
    public var foregroundMemory: Int
    public var foregroundWatchdog: Int
    public var foregroundAbnormal: Int
    public var backgroundMemory: Int

    public init(foregroundMemory: Int = 0, foregroundWatchdog: Int = 0, foregroundAbnormal: Int = 0, backgroundMemory: Int = 0) {
        self.foregroundMemory = foregroundMemory
        self.foregroundWatchdog = foregroundWatchdog
        self.foregroundAbnormal = foregroundAbnormal
        self.backgroundMemory = backgroundMemory
    }
}

/// The counts of one MetricKit diagnostic payload.
public protocol MidgarDiagnosticPayload: Sendable {
    var crashCount: Int { get }
    var hangCount: Int { get }
    var diskWriteCount: Int { get }
    var cpuExceptionCount: Int { get }
}

/// One bucket of a MetricKit histogram: the range it covers and how many samples fell in it.
struct MidgarHistogramBucket: Sendable, Equatable {
    let start: Double
    let end: Double
    let count: Int

    var midpoint: Double {
        (start + end) / 2
    }
}

enum MidgarHistogram {
    /// The midpoint of the bucket holding the middle sample, or nil for an empty histogram.
    static func median(_ buckets: [MidgarHistogramBucket]) -> Double? {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else {
            return nil
        }
        let target = (total + 1) / 2
        var seen = 0
        for bucket in buckets.sorted(by: { $0.start < $1.start }) {
            seen += bucket.count
            if seen >= target {
                return bucket.midpoint
            }
        }
        return nil
    }

    /// The sum of every sample, each counted at its bucket's midpoint.
    static func total(_ buckets: [MidgarHistogramBucket]) -> Double {
        buckets.reduce(0) { $0 + $1.midpoint * Double($1.count) }
    }
}

extension MidgarSignals {
    /// Sends one `metrics.daily` event for a daily MetricKit payload, with the props `coldLaunchMs`, `hangSecondsPerHour`, `foregroundSeconds` and `peakMemoryMB`. Where the payload counts how the app's runs ended it also sends `metrics.exits`, and `health.crashed` once for a day the system ended the app in the foreground for memory or for not responding.
    public func recordDailyMetrics(_ payload: some MidgarMetricPayload) {
        send(.metricsDaily(
            coldLaunchMs: payload.coldLaunchMedianMilliseconds,
            hangSecondsPerHour: payload.hangSecondsPerHour,
            foregroundSeconds: payload.cumulativeForegroundSeconds,
            peakMemoryMB: payload.peakMemoryMegabytes
        ))
        guard let exits = payload.exits else {
            return
        }
        send(.metricsExits(
            foregroundMemory: exits.foregroundMemory,
            foregroundWatchdog: exits.foregroundWatchdog,
            foregroundAbnormal: exits.foregroundAbnormal,
            backgroundMemory: exits.backgroundMemory
        ))
        if exits.foregroundMemory > 0 {
            send(.healthCrashed(kind: .memory))
        }
        if exits.foregroundWatchdog > 0 {
            send(.healthCrashed(kind: .watchdog))
        }
    }

    /// Sends one `metrics.diagnostics` event for a MetricKit diagnostic payload, with the counts `crashes`, `hangs`, `diskWrites` and `cpuExceptions`, and `health.crashed` once for a day with a crash and once for a day with a freeze.
    public func recordDiagnostics(_ payload: some MidgarDiagnosticPayload) {
        send(.metricsDiagnostics(
            crashes: payload.crashCount,
            hangs: payload.hangCount,
            diskWrites: payload.diskWriteCount,
            cpuExceptions: payload.cpuExceptionCount
        ))
        if payload.crashCount > 0 {
            send(.healthCrashed(kind: .crash))
        }
        if payload.hangCount > 0 {
            send(.healthCrashed(kind: .hang))
        }
    }
}
