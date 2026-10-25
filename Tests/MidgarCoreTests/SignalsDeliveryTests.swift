import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsDeliveryTests {
    @Test func offlineKeepsTheEventsAndTheNextFlushSendsThemAgain() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.failing(.notConnectedToInternet), acceptedReply])
        let signals = harness.makeSignals()
        await signals.record("app.launch")
        await signals.record("onboarding.complete")

        await signals.flush()
        #expect(await signals.pendingCount == 2)
        #expect(harness.queueFileExists)

        await signals.flush()
        #expect(await signals.pendingCount == 0)
        #expect(harness.sentBatches.map(\.count) == [2, 2])
    }

    @Test func aServerErrorKeepsTheEvents() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.json(503, #"{"error":{"code":"unavailable","message":"later"}}"#)])
        let signals = harness.makeSignals()
        await signals.record("app.launch")

        await signals.flush()

        #expect(await signals.pendingCount == 1)
        #expect(harness.logs.lines.isEmpty)
    }

    @Test func aFailedDrainStopsAtTheFailedBatch() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.seed((0..<120).map { (name: "tap", props: ["n": .int($0)]) })
        harness.host.enqueue([acceptedReply, .json(500, "{}")])
        let signals = harness.makeSignals()

        await signals.flush()

        #expect(harness.host.requests.count == 2)
        #expect(await signals.pendingCount == 70)
    }

    @Test func aRefusedBatchIsDroppedAndOnlyTheFirstRefusalIsLogged() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([
            .json(400, #"{"error":{"code":"invalid_request","message":"bad"}}"#),
            .json(413, #"{"error":{"code":"payload_too_large","message":"big"}}"#)
        ])
        let signals = harness.makeSignals()

        await signals.record("app.launch")
        await signals.flush()
        #expect(await signals.pendingCount == 0)
        #expect(harness.logs.lines.count == 1)
        #expect(harness.logs.lines.first?.contains("HTTP 400") == true)

        await signals.record("app.launch")
        await signals.flush()
        #expect(await signals.pendingCount == 0)
        #expect(harness.logs.lines.count == 1)
        #expect(!harness.queueFileExists)
    }

    @Test func tooManyRequestsKeepsTheEventsAndWaitsForRetryAfter() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([
            .json(429, #"{"error":{"code":"rate_limited","message":"slow"}}"#, headers: ["Retry-After": "30"]),
            acceptedReply
        ])
        let signals = harness.makeSignals()
        await signals.record("app.launch")

        await signals.flush()
        #expect(await signals.pendingCount == 1)
        #expect(await eventually { await harness.gate.durations.contains(30) })

        harness.clock.advance(by: 29)
        await signals.flush()
        #expect(harness.host.requests.count == 1)

        harness.clock.advance(by: 2)
        await signals.flush()
        #expect(harness.host.requests.count == 2)
        #expect(await signals.pendingCount == 0)
    }

    @Test func tooManyRequestsWithoutRetryAfterWaitsSixtySeconds() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.json(429, "{}"), acceptedReply])
        let signals = harness.makeSignals()
        await signals.record("app.launch")

        await signals.flush()
        harness.clock.advance(by: 59)
        await signals.flush()
        #expect(harness.host.requests.count == 1)

        harness.clock.advance(by: 2)
        await signals.flush()
        #expect(harness.host.requests.count == 2)
    }

    @Test func theKillSwitchTurnsRecordIntoANoOp() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()

        await signals.record("app.launch")

        #expect(await signals.pendingCount == 0)
        #expect(!harness.queueFileExists)
        #expect(harness.host.requests.isEmpty)
    }

    @Test func theKillSwitchClearsTheQueueAndTheFile() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        await signals.record("app.launch")
        await signals.record("onboarding.complete")
        #expect(await signals.pendingCount == 2)
        await signals.persistPending()
        #expect(harness.queueFileExists)

        harness.config.value = try killedSignalsConfig()
        await signals.record("app.launch")

        #expect(await signals.pendingCount == 0)
        #expect(!harness.queueFileExists)
    }

    @Test func aFlushUnderTheKillSwitchSendsNothingAndClearsEventsFromAnEarlierRun() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.seed([(name: "app.launch", props: [:])])
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()

        await signals.flush()

        #expect(harness.host.requests.isEmpty)
        #expect(await signals.pendingCount == 0)
        #expect(!harness.queueFileExists)
    }

    @Test func recordingResumesWhenTheKillSwitchIsLifted() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()
        await signals.record("app.launch")
        harness.config.value = MidgarConfig()

        await signals.record("app.launch")

        #expect(await signals.pendingCount == 1)
    }
}
