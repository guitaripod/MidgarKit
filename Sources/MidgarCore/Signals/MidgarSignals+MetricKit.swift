#if canImport(MetricKit) && (os(iOS) || os(macOS))
import Foundation
import MetricKit

/// A daily `MXMetricPayload` read into plain numbers, so the payload itself is not kept or sent across actors.
struct MidgarMetricKitMetrics: MidgarMetricPayload {
    let coldLaunchMedianMilliseconds: Double?
    let hangSecondsPerHour: Double?
    let cumulativeForegroundSeconds: Double?
    let peakMemoryMegabytes: Double?
    let exits: MidgarExitCounts?

    init(_ payload: MXMetricPayload) {
        exits = Self.exits(payload)
        let foreground = payload.applicationTimeMetrics?.cumulativeForegroundTime.converted(to: .seconds).value
        coldLaunchMedianMilliseconds = payload.applicationLaunchMetrics.flatMap {
            MidgarHistogram.median(Self.buckets(of: $0.histogrammedTimeToFirstDraw, in: .milliseconds))
        }
        hangSecondsPerHour = Self.hangSecondsPerHour(payload, foregroundSeconds: foreground)
        cumulativeForegroundSeconds = foreground
        peakMemoryMegabytes = payload.memoryMetrics?.peakMemoryUsage.converted(to: .megabytes).value
    }

    /// How often the system ended the app, where MetricKit counts it (iOS). A fault in the foreground is a bad access, an illegal instruction or any other abnormal exit; memory in the background is the limit and the pressure exits together.
    private static func exits(_ payload: MXMetricPayload) -> MidgarExitCounts? {
        #if os(iOS)
        guard let metric = payload.applicationExitMetrics else {
            return nil
        }
        let foreground = metric.foregroundExitData
        let background = metric.backgroundExitData
        return MidgarExitCounts(
            foregroundMemory: foreground.cumulativeMemoryResourceLimitExitCount,
            foregroundWatchdog: foreground.cumulativeAppWatchdogExitCount,
            foregroundAbnormal: foreground.cumulativeBadAccessExitCount + foreground.cumulativeIllegalInstructionExitCount + foreground.cumulativeAbnormalExitCount,
            backgroundMemory: background.cumulativeMemoryResourceLimitExitCount + background.cumulativeMemoryPressureExitCount
        )
        #else
        return nil
        #endif
    }

    /// Total hang time over the hours spent in the foreground, or nil when either is unknown or the app never ran in the foreground.
    private static func hangSecondsPerHour(_ payload: MXMetricPayload, foregroundSeconds: Double?) -> Double? {
        guard let foregroundSeconds, foregroundSeconds > 0, let hangs = payload.applicationResponsivenessMetrics else {
            return nil
        }
        let hangSeconds = MidgarHistogram.total(buckets(of: hangs.histogrammedApplicationHangTime, in: .seconds))
        return hangSeconds / (foregroundSeconds / 3_600)
    }

    private static func buckets(of histogram: MXHistogram<UnitDuration>, in unit: UnitDuration) -> [MidgarHistogramBucket] {
        histogram.bucketEnumerator.allObjects.compactMap { object in
            guard let bucket = object as? MXHistogramBucket<UnitDuration> else {
                return nil
            }
            return MidgarHistogramBucket(
                start: bucket.bucketStart.converted(to: unit).value,
                end: bucket.bucketEnd.converted(to: unit).value,
                count: bucket.bucketCount
            )
        }
    }
}

/// An `MXDiagnosticPayload` reduced to the four counts signals reports.
struct MidgarMetricKitDiagnostics: MidgarDiagnosticPayload {
    let crashCount: Int
    let hangCount: Int
    let diskWriteCount: Int
    let cpuExceptionCount: Int

    init(_ payload: MXDiagnosticPayload) {
        crashCount = payload.crashDiagnostics?.count ?? 0
        hangCount = payload.hangDiagnostics?.count ?? 0
        diskWriteCount = payload.diskWriteExceptionDiagnostics?.count ?? 0
        cpuExceptionCount = payload.cpuExceptionDiagnostics?.count ?? 0
    }
}

/// Receives MetricKit's daily payloads and records them as `metrics.daily`, `metrics.exits` and `metrics.diagnostics`, and each diagnostic as a crash card. It holds only the signals instance and never keeps a payload.
final class MidgarMetricKitSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let signals: MidgarSignals

    init(signals: MidgarSignals) {
        self.signals = signals
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let metrics = payloads.map(MidgarMetricKitMetrics.init)
        let signals = signals
        Task {
            for metric in metrics {
                await signals.recordDailyMetrics(metric)
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let diagnostics = payloads.map(MidgarMetricKitDiagnostics.init)
        let documents = payloads.map { $0.jsonRepresentation() }
        let binaries = MidgarSignalsPlatform.bundleBinaries()
        let trail = MidgarTrail.previousRun()
        let signals = signals
        Task {
            for diagnostic in diagnostics {
                await signals.recordDiagnostics(diagnostic)
            }
            for document in documents {
                await signals.recordDiagnosticJSON(document, appBinaries: binaries, trail: trail)
            }
        }
    }
}

extension MidgarSignals {
    /// Subscribes to MetricKit so each daily metrics payload becomes one `metrics.daily` event and each diagnostic payload one `metrics.diagnostics` event and its crash cards. ``configure(configuration:config:directory:appVersion:)`` calls it for an app, so no app needs to; MetricKit delivers on its own schedule, about once a day.
    public func startCollectingMetrics() {
        guard !isCollectingMetrics else {
            return
        }
        isCollectingMetrics = true
        let subscriber = MidgarMetricKitSubscriber(signals: self)
        retain(subscriber)
        MXMetricManager.shared.add(subscriber)
    }
}
#endif
