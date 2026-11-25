import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsTestInstallTests {
    @Test func aTestFlightInstallSendsNothingAndClearsWhatItQueued() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(isTestInstall: { true })

        await signals.send(.paywallView(placement: .paywall))
        await signals.noteActive()
        await signals.flush()

        #expect(harness.host.requests.isEmpty)
        #expect(await signals.pendingCount == 0)
        #expect(!harness.queueFileExists)
        #expect(harness.logs.lines == ["signals: not an App Store install, usage counts are not sent"])
    }

    @Test func onlyAReceiptStoreKitCallsProductionIsCounted() {
        #expect(!MidgarSignalsInstallSource.isTestInstall(hasReceipt: true, production: true))
        #expect(MidgarSignalsInstallSource.isTestInstall(hasReceipt: true, production: false))
        #expect(!MidgarSignalsInstallSource.isTestInstall(hasReceipt: true, production: nil))
        #expect(MidgarSignalsInstallSource.isTestInstall(hasReceipt: false, production: nil))
        #expect(!MidgarSignalsInstallSource.isTestInstall(hasReceipt: false, production: true))
    }

    @Test func aFlushAndACrashCardAskWhereTheInstallCameFromOnlyOnce() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let asked = SignalsLogRecorder()
        let signals = harness.makeSignals(isTestInstall: {
            asked.record("asked")
            return true
        })

        await signals.record("app.launch")
        await signals.flush()
        await signals.sendPendingCards()

        #expect(asked.lines.count == 1)
        #expect(harness.host.requests.isEmpty)
    }

    @Test func aTestFlightInstallStopsRecordingOnceStoreKitHasAnswered() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(isTestInstall: { true })
        await signals.record("app.launch")
        await signals.flush()

        await signals.record("app.launch")
        await signals.send(.paywallView(placement: .paywall))

        #expect(await signals.pendingCount == 0)
        #expect(harness.host.requests.isEmpty)
    }

    @Test func eventsAnEarlierRunLeftAreNeverSentFromATestInstall() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.seed([(name: "app.launch", props: [:])])
        let signals = harness.makeSignals(isTestInstall: { true })

        await signals.flush()

        #expect(harness.host.requests.isEmpty)
        #expect(!harness.queueFileExists)
    }

    @Test func anAppStoreInstallAsksStoreKitOnceAndSends() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])
        let asked = SignalsLogRecorder()
        let signals = harness.makeSignals(isTestInstall: {
            asked.record("asked")
            return false
        })

        await signals.record("app.launch")
        await signals.flush()
        await signals.send(.paywallView(placement: .paywall))
        await signals.flush()

        #expect(harness.host.requests.count == 2)
        #expect(asked.lines.count == 1)
        #expect(harness.logs.lines.isEmpty)
    }
}
