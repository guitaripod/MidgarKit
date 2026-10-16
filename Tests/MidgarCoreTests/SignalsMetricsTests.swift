import Foundation
import Testing
@testable import MidgarCore

private struct FakeMetrics: MidgarMetricPayload {
    var coldLaunchMedianMilliseconds: Double? = 412.5
    var hangSecondsPerHour: Double? = 0.8
    var cumulativeForegroundSeconds: Double? = 5_400
    var peakMemoryMegabytes: Double? = 187.25
}

private struct FakeDiagnostics: MidgarDiagnosticPayload {
    var crashCount = 1
    var hangCount = 2
    var diskWriteCount = 0
    var cpuExceptionCount = 3
}

@Suite struct SignalsMetricsTests {
    @Test func aMetricPayloadBecomesOneMetricsDailyEvent() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.recordDailyMetrics(FakeMetrics())
        await signals.flush()

        let event = try #require(harness.sentBatches.first?.first)
        #expect(harness.sentBatches.first?.count == 1)
        #expect(event["name"] as? String == "metrics.daily")
        let props = try #require(event["props"] as? [String: Double])
        #expect(props == [
            "coldLaunchMs": 412.5,
            "hangSecondsPerHour": 0.8,
            "foregroundSeconds": 5_400,
            "peakMemoryMB": 187.25
        ])
    }

    @Test func aMetricMissingFromThePayloadIsLeftOutOfTheEvent() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.recordDailyMetrics(FakeMetrics(coldLaunchMedianMilliseconds: nil, hangSecondsPerHour: nil))
        await signals.flush()

        let props = try #require(harness.sentBatches.first?.first?["props"] as? [String: Double])
        #expect(Set(props.keys) == ["foregroundSeconds", "peakMemoryMB"])
    }

    @Test func aDiagnosticPayloadBecomesOneMetricsDiagnosticsEventWithCounts() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.recordDiagnostics(FakeDiagnostics())
        await signals.flush()

        let event = try #require(harness.sentBatches.first?.first)
        #expect(event["name"] as? String == "metrics.diagnostics")
        let props = try #require(event["props"] as? [String: Int])
        #expect(props == ["crashes": 1, "hangs": 2, "diskWrites": 0, "cpuExceptions": 3])
    }

    @Test func metricEventsFollowTheKillSwitch() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()

        await signals.recordDailyMetrics(FakeMetrics())
        await signals.recordDiagnostics(FakeDiagnostics())

        #expect(await signals.pendingCount == 0)
    }

    @Test func theHistogramMedianIsTheMidpointOfTheMiddleSample() {
        let buckets = [
            MidgarHistogramBucket(start: 0, end: 100, count: 1),
            MidgarHistogramBucket(start: 200, end: 300, count: 3),
            MidgarHistogramBucket(start: 100, end: 200, count: 1)
        ]
        #expect(MidgarHistogram.median(buckets) == 250)
        #expect(MidgarHistogram.median([]) == nil)
        #expect(MidgarHistogram.median([MidgarHistogramBucket(start: 0, end: 10, count: 0)]) == nil)
    }

    @Test func theHistogramTotalCountsEachSampleAtItsMidpoint() {
        let buckets = [
            MidgarHistogramBucket(start: 0, end: 2, count: 4),
            MidgarHistogramBucket(start: 2, end: 4, count: 1)
        ]
        #expect(MidgarHistogram.total(buckets) == 7)
    }
}
