import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsUniquenessTests {
    private func names(_ sent: [(name: String, props: [String: Any])]) -> [String] {
        sent.map(\.name)
    }

    @Test func eachSendsEveryTime() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallView(placement: .settings))

        #expect(await signals.pendingCount == 3)
    }

    @Test func dailySendsOncePerCalendarDayPerPropCombination() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .day)

        for _ in 0..<3 { await signals.deliver(name: "d", props: ["k": "a"], uniqueness: .daily, carriesCohort: false) }
        await signals.deliver(name: "d", props: ["k": "b"], uniqueness: .daily, carriesCohort: false)
        await signals.deliver(name: "d", props: [:], uniqueness: .daily, carriesCohort: false)
        #expect(await signals.pendingCount == 3)

        harness.clock.advance(by: 3_600 * 6)
        await signals.deliver(name: "d", props: ["k": "a"], uniqueness: .daily, carriesCohort: false)
        #expect(await signals.pendingCount == 3)

        harness.advance(toNext: .day)
        await signals.deliver(name: "d", props: ["k": "a"], uniqueness: .daily, carriesCohort: false)
        await signals.deliver(name: "d", props: ["k": "a"], uniqueness: .daily, carriesCohort: false)
        #expect(await signals.pendingCount == 4)
    }

    @Test func weeklySendsOncePerISOWeek() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .weekOfYear)

        await signals.deliver(name: "w", props: [:], uniqueness: .weekly, carriesCohort: false)
        harness.clock.advance(by: 3_600 * 24 * 3)
        await signals.deliver(name: "w", props: [:], uniqueness: .weekly, carriesCohort: false)
        #expect(await signals.pendingCount == 1)

        harness.advance(toNext: .weekOfYear)
        await signals.deliver(name: "w", props: [:], uniqueness: .weekly, carriesCohort: false)
        await signals.deliver(name: "w", props: [:], uniqueness: .weekly, carriesCohort: false)
        #expect(await signals.pendingCount == 2)
    }

    @Test func monthlySendsOncePerCalendarMonth() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .month)

        await signals.deliver(name: "m", props: ["k": 1], uniqueness: .monthly, carriesCohort: false)
        harness.clock.advance(by: 3_600 * 24 * 20)
        await signals.deliver(name: "m", props: ["k": 1], uniqueness: .monthly, carriesCohort: false)
        await signals.deliver(name: "m", props: ["k": 2], uniqueness: .monthly, carriesCohort: false)
        #expect(await signals.pendingCount == 2)

        harness.advance(toNext: .month)
        await signals.deliver(name: "m", props: ["k": 1], uniqueness: .monthly, carriesCohort: false)
        #expect(await signals.pendingCount == 3)
    }

    @Test func lifetimeSendsOncePerInstallPerPropCombinationForever() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.funnelStep(step: .libraryFilled))
        #expect(await signals.pendingCount == 2)

        harness.clock.advance(by: 3_600 * 24 * 400)
        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.funnelStep(step: .trialStarted))
        #expect(await signals.pendingCount == 3)
    }

    @Test func perPeriodSendsEachPeriodOncePerPeriod() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .month)

        await signals.noteActive()
        await signals.noteActive()
        #expect(await signals.pendingCount == 3)

        harness.clock.advance(by: 3_600 * 2)
        await signals.noteActive()
        #expect(await signals.pendingCount == 3)

        harness.advance(toNext: .day)
        await signals.noteActive()
        #expect(await signals.pendingCount == 4)

        harness.advance(toNext: .weekOfYear)
        await signals.noteActive()
        #expect(await signals.pendingCount >= 6)

        harness.advance(toNext: .month)
        await signals.noteActive()
        let sent = await harness.drain(signals)
        let periods = sent.compactMap { ($0.props["period"] as? String) }
        #expect(periods.filter { $0 == "month" }.count == 2)
        #expect(periods.filter { $0 == "day" }.count == 4)
    }

    @Test func aPerPeriodEventWithoutAKnownPeriodIsSentEveryTime() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.deliver(name: "app.active", props: ["period": "decade"], uniqueness: .perPeriod, carriesCohort: false)
        await signals.deliver(name: "app.active", props: ["period": "decade"], uniqueness: .perPeriod, carriesCohort: false)

        #expect(await signals.pendingCount == 2)
    }

    @Test func nothingIsRememberedWhileTheKillSwitchIsOn() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()

        await signals.send(.funnelStep(step: .samplePlayed))
        #expect(await signals.pendingCount == 0)

        harness.config.value = MidgarConfig()
        await signals.send(.funnelStep(step: .samplePlayed))
        #expect(await signals.pendingCount == 1)
    }

    @Test func aTypedSendPutsTheSameEventOnTheWireAsTheOldRecord() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        let events: [MidgarSignal] = [
            .paywallView(placement: .paywall),
            .paywallPurchase(product: "com.example.pro"),
            .paywallCheckout(outcome: .failed, product: "com.example.pro"),
            .impression(appId: "6746733380", storefront: .fi, placement: .entry),
            .portalOpen(placement: .settings),
            .metricsDaily(coldLaunchMs: 420.5, peakMemoryMB: 180),
            .metricsDiagnostics(crashes: 1, hangs: 0),
        ]

        for event in events { await signals.send(event) }
        let typed = await harness.drain(signals)
        for event in events { await signals.record(event.name, props: event.props) }
        let recorded = await harness.drain(signals)

        #expect(typed.count == events.count)
        #expect(typed.map(\.name) == recorded.map(\.name))
        for (left, right) in zip(typed, recorded) {
            #expect(NSDictionary(dictionary: left.props).isEqual(to: right.props))
        }
    }
}
