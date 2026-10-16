import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsBatchingTests {
    @Test func nothingIsSentBelowTheThresholdAndTheTwentiethEventStartsAFlush() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await recordTaps(signals, 0..<19)
        await signals.waitForIdle()
        #expect(harness.host.requests.isEmpty)
        #expect(await signals.pendingCount == 19)

        await recordTaps(signals, 19..<20)
        await signals.waitForIdle()
        #expect(harness.sentBatches.map(\.count) == [20])
        #expect(await signals.pendingCount == 0)
    }

    @Test func aLoneEventIsSentWhenTheSixtySecondTimerFires() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.record("app.launch")
        #expect(await eventually { await harness.gate.durations == [60] })
        #expect(harness.host.requests.isEmpty)

        await harness.gate.fireAll()
        #expect(await eventually { harness.host.requests.count == 1 })
        await signals.waitForIdle()
        #expect(await signals.pendingCount == 0)
        #expect(harness.sentBatches.first?.first?["name"] as? String == "app.launch")
    }

    @Test func automaticRequestsAreAtLeastTenSecondsApart() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])
        let signals = harness.makeSignals()

        await recordTaps(signals, 0..<20)
        await signals.waitForIdle()
        await recordTaps(signals, 20..<40)
        await signals.waitForIdle()
        #expect(harness.host.requests.count == 1)
        #expect(await signals.pendingCount == 20)
        #expect(await eventually { await harness.gate.durations.contains(10) })

        harness.clock.advance(by: 10)
        await harness.gate.fireAll()
        #expect(await eventually { harness.host.requests.count == 2 })
        await signals.waitForIdle()
        #expect(await signals.pendingCount == 0)
    }

    @Test func aFlushSplitsTheQueueIntoBatchesOfFiftyEvents() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.seed((0..<120).map { (name: "tap", props: ["n": .int($0)]) })
        harness.host.enqueue([acceptedReply, acceptedReply, acceptedReply])
        let signals = harness.makeSignals()

        await signals.flush()

        #expect(harness.sentBatches.map(\.count) == [50, 50, 20])
        #expect(await signals.pendingCount == 0)
        let order = harness.sentBatches.joined().compactMap { ($0["props"] as? [String: Int])?["n"] }
        #expect(order == Array(0..<120))
    }

    @Test func aFlushSplitsTheQueueBeforeABatchPasses32Kilobytes() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let wide = Dictionary(uniqueKeysWithValues: (0..<20).map { ("key\($0)", MidgarSignalValue.string(String(repeating: "x", count: 64))) })
        harness.seed((0..<40).map { _ in (name: "tap", props: wide) })
        harness.host.enqueue([acceptedReply, acceptedReply, acceptedReply, acceptedReply])
        let signals = harness.makeSignals()

        await signals.flush()

        let requests = harness.host.requests
        #expect(requests.count >= 2)
        #expect(requests.allSatisfy { ($0.body?.count ?? 0) <= 32 * 1024 })
        #expect(requests.allSatisfy { ($0.body?.count ?? 0) > 16 * 1024 || $0.body == requests.last?.body })
        #expect(harness.sentBatches.map(\.count).reduce(0, +) == 40)
        #expect(await signals.pendingCount == 0)
    }

    @Test func aFullQueueDropsTheOldestEventsFirst() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.failing(.notConnectedToInternet)])
        let signals = harness.makeSignals()

        await recordTaps(signals, 0..<520)
        await signals.waitForIdle()
        #expect(await signals.pendingCount == 500)

        harness.host.enqueue(Array(repeating: acceptedReply, count: 10))
        await signals.flush()
        let sent = harness.sentBatches.dropFirst().joined().compactMap { ($0["props"] as? [String: Int])?["n"] }
        #expect(sent == Array(20..<520))
        #expect(await signals.pendingCount == 0)
    }

    @Test func unsentEventsSurviveARelaunch() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals()
        await first.record("paywall.view", props: ["placement": "settings"])
        await first.record("app.launch")
        #expect(harness.queueFileExists)

        let second = harness.makeSignals()
        #expect(await second.pendingCount == 2)
        harness.host.enqueue([acceptedReply])
        await second.flush()

        let names = harness.sentBatches.first?.compactMap { $0["name"] as? String }
        #expect(names == ["paywall.view", "app.launch"])
        #expect(!harness.queueFileExists)
    }

    @Test func eventsLoadedFromDiskAreSentWhenTheTimerFires() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.seed([(name: "app.launch", props: [:])])
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        #expect(await eventually { await harness.gate.durations == [60] })
        await harness.gate.fireAll()
        #expect(await eventually { harness.host.requests.count == 1 })
        await signals.waitForIdle()
    }

    @Test func aCorruptQueueFileIsIgnored() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let store = MidgarSignalsStore(directory: harness.directory, appID: harness.appID)
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        let signals = harness.makeSignals()

        #expect(await signals.pendingCount == 0)
    }
}
