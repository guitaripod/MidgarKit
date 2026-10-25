import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsLedgerTests {
    @Test func theLedgerSurvivesARelaunch() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals()
        await first.send(.funnelStep(step: .samplePlayed))
        await first.noteActive()
        _ = await harness.drain(first)

        let relaunched = harness.makeSignals()
        await relaunched.send(.funnelStep(step: .samplePlayed))
        await relaunched.noteActive()
        await relaunched.send(.funnelStep(step: .libraryFilled))

        #expect(await relaunched.pendingCount == 1)
    }

    @Test func entriesOfPassedPeriodsArePrunedOnTheNextWriteAndLifetimeEntriesStay() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .month)
        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.noteActive()
        await signals.deliver(name: "d", props: [:], uniqueness: .daily, carriesCohort: false)
        await signals.persistPending()
        #expect(harness.ledgerOnDisk.count == 5)

        harness.advance(toNext: .month)
        await signals.deliver(name: "d", props: [:], uniqueness: .daily, carriesCohort: false)
        await signals.persistPending()

        let marks = harness.ledgerOnDisk
        let keys = MidgarSignalPeriodKeys(at: harness.clock.now)
        #expect(marks == [
            "funnel.step|step=sample_played": "lifetime",
            "d": keys.day,
        ])
    }

    @Test func sendingDoesNotWriteToDiskPerCallAndTheLedgerFollowsOnFlush() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        for step in MidgarSignal.FunnelStep.allCases { await signals.send(.funnelStep(step: step)) }
        await signals.send(.paywallView(placement: .paywall))

        #expect(await signals.writeCount == 0)
        #expect(!harness.ledgerFileExists)
        #expect(!harness.queueFileExists)

        await signals.persistPending()
        #expect(await signals.writeCount == 2)
        #expect(harness.ledgerOnDisk.count == 6)
        #expect(harness.queueFileExists)
    }

    @Test func theLedgerIsWrittenOnItsOwnAfterTheWriteDelay() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(policy: MidgarSignalsPolicy.standard.persisting(after: 0.05))

        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.funnelStep(step: .libraryFilled))

        #expect(await eventually { harness.ledgerOnDisk.count == 2 })
        #expect(await signals.writeCount == 2)
    }

    @Test func manyChangesInsideTheDelayAreOneWrite() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(policy: MidgarSignalsPolicy.standard.persisting(after: 0.2))

        for index in 0..<50 { await signals.deliver(name: "d", props: ["n": .int(index)], uniqueness: .daily, carriesCohort: false) }

        #expect(await eventually { harness.ledgerFileExists })
        #expect(await signals.writeCount == 2)
    }

    @Test func aLedgerThatCannotBeReadStartsEmpty() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: harness.ledgerFile)
        let signals = harness.makeSignals()

        await signals.send(.funnelStep(step: .samplePlayed))

        #expect(await signals.pendingCount == 1)
    }

    @Test func theLedgerStopsRememberingPastItsCapacityButStillSends() {
        var ledger = MidgarSignalsLedger()
        var allNew = true
        for index in 0..<MidgarSignalsLedger.capacity {
            allNew = ledger.claim(key: "k\(index)", mark: MidgarSignalsLedger.lifetimeMark) && allNew
        }
        let overflowFirst = ledger.claim(key: "overflow", mark: MidgarSignalsLedger.lifetimeMark)
        let overflowAgain = ledger.claim(key: "overflow", mark: MidgarSignalsLedger.lifetimeMark)
        let known = ledger.claim(key: "k0", mark: MidgarSignalsLedger.lifetimeMark)

        #expect(allNew)
        #expect(overflowFirst)
        #expect(overflowAgain)
        #expect(ledger.marks.count == MidgarSignalsLedger.capacity)
        #expect(!known)
    }

    @Test func keysNameTheEventAndItsPropsInOrder() {
        #expect(MidgarSignalsLedger.key(name: "tap", props: [:]) == "tap")
        #expect(MidgarSignalsLedger.key(name: "tap", props: ["b": 2, "a": "x", "c": true]) == "tap|a=x|b=2|c=true")
    }
}
