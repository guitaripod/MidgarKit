import Foundation

/// The numbers of one daily MetricKit metrics payload, read into plain values. A value MetricKit did not report is nil and is left out of the event.
public protocol MidgarMetricPayload: Sendable {
    /// Median time to first draw of a cold launch, in milliseconds.
    var coldLaunchMedianMilliseconds: Double? { get }
    /// Seconds spent hanging per hour in the foreground.
    var hangSecondsPerHour: Double? { get }
    var cumulativeForegroundSeconds: Double? { get }
    var peakMemoryMegabytes: Double? { get }
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
    /// Records one `metrics.daily` event for a daily MetricKit payload, with the props `coldLaunchMs`, `hangSecondsPerHour`, `foregroundSeconds` and `peakMemoryMB`.
    public func recordDailyMetrics(_ payload: some MidgarMetricPayload) {
        record("metrics.daily", props: Self.props(for: payload))
    }

    /// Records one `metrics.diagnostics` event for a MetricKit diagnostic payload, with the counts `crashes`, `hangs`, `diskWrites` and `cpuExceptions`.
    public func recordDiagnostics(_ payload: some MidgarDiagnosticPayload) {
        record("metrics.diagnostics", props: Self.props(for: payload))
    }

    static func props(for payload: some MidgarMetricPayload) -> [String: MidgarSignalValue] {
        var props: [String: MidgarSignalValue] = [:]
        if let value = payload.coldLaunchMedianMilliseconds { props["coldLaunchMs"] = .double(value) }
        if let value = payload.hangSecondsPerHour { props["hangSecondsPerHour"] = .double(value) }
        if let value = payload.cumulativeForegroundSeconds { props["foregroundSeconds"] = .double(value) }
        if let value = payload.peakMemoryMegabytes { props["peakMemoryMB"] = .double(value) }
        return props
    }

    static func props(for payload: some MidgarDiagnosticPayload) -> [String: MidgarSignalValue] {
        [
            "crashes": .int(payload.crashCount),
            "hangs": .int(payload.hangCount),
            "diskWrites": .int(payload.diskWriteCount),
            "cpuExceptions": .int(payload.cpuExceptionCount)
        ]
    }
}
