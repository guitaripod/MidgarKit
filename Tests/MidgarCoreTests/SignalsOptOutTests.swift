import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsOptOutTests {
    @Test func usageCountsAreOnByDefault() {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        #expect(harness.makeSignals().isEnabled)
    }

    @Test func turningThemOffEmptiesTheQueueAndDeletesTheLedger() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.paywallView(placement: .paywall))
        await signals.persistPending()
        #expect(harness.queueFileExists)
        #expect(harness.ledgerFileExists)

        signals.setEnabled(false)
        await signals.applyConsent()

        #expect(!signals.isEnabled)
        #expect(await signals.pendingCount == 0)
        #expect(!harness.queueFileExists)
        #expect(!harness.ledgerFileExists)
    }

    @Test func nothingIsRecordedOrSentWhileTheyAreOff() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        signals.setEnabled(false)

        await signals.send(.paywallView(placement: .paywall))
        await signals.record("app.launch")
        await signals.noteActive()
        await signals.flush()

        #expect(await signals.pendingCount == 0)
        #expect(harness.host.requests.isEmpty)
        #expect(!harness.queueFileExists)
        #expect(!harness.ledgerFileExists)
    }

    @Test func theChoiceIsKeptAcrossLaunches() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals()
        first.setEnabled(false)
        await first.applyConsent()

        let relaunched = harness.makeSignals()
        #expect(!relaunched.isEnabled)
        await relaunched.send(.paywallView(placement: .paywall))
        #expect(await relaunched.pendingCount == 0)

        relaunched.setEnabled(true)
        await relaunched.applyConsent()
        let again = harness.makeSignals()
        #expect(again.isEnabled)
    }

    @Test func eventsFromAnEarlierRunAreClearedByTheFirstFlushWhileOff() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals()
        first.setEnabled(false)
        await first.applyConsent()
        harness.seed([(name: "app.launch", props: [:])])

        let relaunched = harness.makeSignals()
        await relaunched.flush()

        #expect(harness.host.requests.isEmpty)
        #expect(await relaunched.pendingCount == 0)
        #expect(!harness.queueFileExists)
    }

    @Test func turningThemBackOnForgetsWhatWasSentBeforeButKeepsTheCohort() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        let week = MidgarSignals.periodKey(.week, at: harness.clock.now, calendar: MidgarSignals.activityCalendar)
        await signals.send(.funnelStep(step: .samplePlayed))

        signals.setEnabled(false)
        await signals.applyConsent()
        signals.setEnabled(true)
        await signals.applyConsent()
        harness.advance(toNext: .weekOfYear)
        await signals.send(.funnelStep(step: .samplePlayed))
        let sent = await harness.drain(signals)

        #expect(sent.count == 1)
        #expect(sent.first?.props["cohort"] as? String == week)
    }
}
