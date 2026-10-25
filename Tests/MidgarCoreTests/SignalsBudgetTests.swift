import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsBudgetTests {
    private static let calls = 10_000

    /// Runs `body` for every call and returns the seconds the whole loop took, with the actor warmed up first.
    private func measure(_ signals: MidgarSignals, _ body: (MidgarSignals) async -> Void) async -> TimeInterval {
        await body(signals)
        let start = ContinuousClock.now
        for _ in 0..<Self.calls { await body(signals) }
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    @Test func tenThousandDedupedSendsAreCheapAndWriteNothing() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        let seconds = await measure(signals) { await $0.send(.funnelStep(step: .samplePlayed)) }

        print("signals budget: deduped send \(seconds / Double(Self.calls) * 1e6) microseconds per call")
        #expect(seconds < 2.0)
        #expect(await signals.pendingCount == 1)
        #expect(await signals.writeCount == 0)
        #expect(!harness.ledgerFileExists)
    }

    @Test func tenThousandEachSendsAreCheapAndWriteNothing() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        let seconds = await measure(signals) { await $0.send(.paywallView(placement: .paywall)) }

        print("signals budget: each send \(seconds / Double(Self.calls) * 1e6) microseconds per call")
        #expect(seconds < 2.0)
        #expect(await signals.pendingCount == 500)
        #expect(await signals.writeCount == 0)
        #expect(!harness.queueFileExists)
    }
}
