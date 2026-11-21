import Foundation
import Testing
@testable import MidgarCore

/// Context and stories: what the install remembers decides which closed-set word an event carries, and a story waits before it is sent.
@Suite struct SignalsContextTests {
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 86_400

    private func quickStories() -> MidgarSignalsPolicy {
        var policy = MidgarSignalsPolicy.standard
        policy.storyDelay = hour...hour
        return policy
    }

    private func named(_ name: String, in sent: [(name: String, props: [String: Any])]) -> [[String: String]] {
        sent.filter { $0.name == name }.map { $0.props.compactMapValues { $0 as? String } }
    }

    private func contextFile(_ harness: SignalsHarness) -> URL {
        MidgarSignalsContextStore(store: MidgarSignalsStore(directory: harness.directory, appID: harness.appID)).fileURL
    }

    @Test func theTierTheStoreReportsIsStampedOnTheEventsThatDeclareIt() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.note(.tier(.paid))
        await signals.send(.featureUse(feature: "player"))
        await signals.send(.paywallView(placement: .settings))
        let sent = await harness.drain(signals)

        #expect(named("app.tier", in: sent) == [["tier": "paid"]])
        #expect(named("feature.use", in: sent) == [["feature": "player", "tier": "paid"]])
        #expect(named("paywall.view", in: sent) == [["placement": "settings"]])
    }

    @Test func aChangeOfTierInsideAWeekCountsNothingTwice() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        harness.align(to: .weekOfYear)

        await signals.note(.tier(.free))
        await signals.send(.featureUse(feature: "player"))
        await signals.note(.tier(.paid))
        await signals.send(.featureUse(feature: "player"))
        await signals.send(.featureUse(feature: "library"))
        let sent = await harness.drain(signals)

        #expect(named("app.tier", in: sent) == [["tier": "free"]])
        #expect(named("feature.use", in: sent) == [["feature": "player", "tier": "free"], ["feature": "library", "tier": "paid"]])
    }

    @Test func anInstallWhoseTierIsUnknownIsNotCountedByTier() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.noteActive()
        await signals.send(.featureUse(feature: "player"))
        let first = await harness.drain(signals)
        #expect(named("app.tier", in: first).isEmpty)
        #expect(named("feature.use", in: first) == [["feature": "player", "tier": "unknown"]])

        await signals.note(.tier(.trial))
        #expect(named("app.tier", in: await harness.drain(signals)) == [["tier": "trial"]])
        harness.advance(toNext: .weekOfYear)
        await signals.noteActive()
        await signals.noteActive()
        #expect(named("app.tier", in: await harness.drain(signals)) == [["tier": "trial"]])
    }

    @Test func aPurchaseStoryWaitsAndCarriesWhatTheInstallRemembers() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let installed = harness.clock.now.addingTimeInterval(-3 * day)
        let signals = harness.makeSignals(installDate: { installed }, policy: quickStories())

        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallView(placement: .limit))
        await signals.note(.purchased)
        let early = await harness.drain(signals)
        #expect(early.map(\.name) == ["paywall.view", "paywall.view"])

        harness.clock.advance(by: hour - 1)
        #expect(named("purchase.story", in: await harness.drain(signals)).isEmpty)

        harness.clock.advance(by: 1)
        #expect(named("purchase.story", in: await harness.drain(signals)) == [["placement": "limit", "viewsBefore": "two_three", "age": "week1"]])
        #expect(await harness.drain(signals).isEmpty)
    }

    @Test func aPurchaseWithNoPurchaseScreenBeforeItSaysSo() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(policy: quickStories())

        await signals.note(.purchased)
        harness.clock.advance(by: hour)

        #expect(named("purchase.story", in: await harness.drain(signals)) == [["viewsBefore": "none", "age": "unknown"]])
    }

    @Test func aHeldStoryAndTheTierSurviveARelaunch() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals(policy: quickStories())
        await first.note(.tier(.paid))
        await first.send(.paywallView(placement: .moment))
        await first.note(.purchased)
        _ = await harness.drain(first)

        harness.clock.advance(by: 2 * hour)
        let relaunched = harness.makeSignals(policy: quickStories())
        await relaunched.noteActive()
        await relaunched.send(.featureUse(feature: "player"))
        let sent = await harness.drain(relaunched)

        #expect(named("purchase.story", in: sent) == [["placement": "moment", "viewsBefore": "one", "age": "unknown"]])
        #expect(named("feature.use", in: sent) == [["feature": "player", "tier": "paid"]])
    }

    @Test func theStandardWaitIsSixToFortyEightHours() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        let start = harness.clock.now

        for _ in 0..<12 { await signals.note(.purchased) }
        await signals.flush()

        let held = try #require(MidgarSignalsContextStore(store: MidgarSignalsStore(directory: harness.directory, appID: harness.appID)).load()).held
        #expect(held.count == 12)
        #expect(held.allSatisfy { (6 * hour...48 * hour).contains($0.releaseAt.timeIntervalSince(start)) })
        #expect(Set(held.map(\.releaseAt)).count > 1)
        #expect(await signals.pendingCount == 0)
    }

    @Test func turningCountsOffForgetsTheContextAndTheStories() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(policy: quickStories())
        await signals.note(.tier(.paid))
        await signals.note(.purchased)
        await signals.flush()
        #expect(FileManager.default.fileExists(atPath: contextFile(harness).path))

        signals.setEnabled(false)
        #expect(await eventually { !FileManager.default.fileExists(atPath: contextFile(harness).path) })
        await signals.note(.purchased)
        await signals.noteValue()
        signals.setEnabled(true)
        #expect(await eventually { await signals.isEnabled })
        harness.clock.advance(by: 2 * hour)
        await signals.send(.featureUse(feature: "player"))

        let sent = await harness.drain(signals)
        #expect(named("purchase.story", in: sent).isEmpty)
        #expect(named("feature.use", in: sent) == [["feature": "player", "tier": "unknown"]])
    }

    @Test func aTestInstallHoldsAndSendsNoStory() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(isTestInstall: { true }, policy: quickStories())
        await signals.note(.purchased)
        await signals.send(.paywallView(placement: .entry))
        await signals.flush()
        harness.clock.advance(by: 2 * hour)
        await signals.note(.purchased)
        await signals.flush()

        #expect(harness.sentBatches.isEmpty)
        #expect(await signals.context?.held.isEmpty != false)
    }

    @Test func theValueMomentIsSentOnceWithHowSoonItCame() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let installed = harness.clock.now.addingTimeInterval(-600)
        let signals = harness.makeSignals(installDate: { installed })

        await signals.noteValue()
        await signals.noteValue()
        let sent = await harness.drain(signals)
        #expect(named("value.first", in: sent).map { $0["within"] } == ["first_session"])
        #expect(named("value.first", in: sent).first?["cohort"] != nil)

        let relaunched = harness.makeSignals(installDate: { installed })
        await relaunched.noteValue()
        #expect(await harness.drain(relaunched).isEmpty)
    }

    @Test func aValueMomentInALaterRunIsNotAFirstSession() async {
        for (age, expected) in [(600.0, "day0"), (3 * day, "week1"), (40 * day, "later")] {
            let harness = SignalsHarness()
            defer { harness.cleanUp() }
            let installed = harness.clock.now.addingTimeInterval(-age)
            let first = harness.makeSignals(installDate: { installed })
            await first.noteActive()
            await first.flush()

            let later = harness.makeSignals(installDate: { installed })
            await later.noteValue()
            #expect(named("value.first", in: await harness.drain(later)).map { $0["within"] } == [expected])
        }
    }

    @Test func aRenewalTurnedOffCarriesHowLongItRanAndHowMuchTheAppWasUsed() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(policy: quickStories())
        let started = harness.clock.now.addingTimeInterval(-100 * day)

        for _ in 0..<3 {
            await signals.noteActive()
            await signals.noteActive()
            harness.clock.advance(by: day)
        }
        harness.clock.advance(by: 20 * day)
        await signals.noteActive()
        await signals.note(.renewalOff(startedAt: started))
        harness.clock.advance(by: hour)

        #expect(named("renewal.off", in: await harness.drain(signals)) == [["tenure": "half1", "activeDays": "one_two"]])
    }

    @Test func theBucketsBreakWhereTheRegistrySaysTheyDo() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func age(_ days: Double) -> MidgarSignal.Age { MidgarSignalsBuckets.age(installedAt: now.addingTimeInterval(-days * 86_400), now: now) }
        #expect([age(0), age(0.99), age(1), age(6.9), age(7), age(27.9), age(28), age(89.9), age(90)] == [.day0, .day0, .week1, .week1, .month1, .month1, .quarter1, .quarter1, .older])
        #expect(age(-2) == .day0)
        #expect(MidgarSignalsBuckets.age(installedAt: nil, now: now) == .unknown)
        #expect(MidgarSignalsBuckets.age(installedAt: Date(timeIntervalSince1970: 0), now: now) == .unknown)
        #expect([0, 1, 2, 3, 4, 9, 10, 500].map(MidgarSignalsBuckets.views) == [.none, .one, .twoThree, .twoThree, .fourNine, .fourNine, .tenPlus, .tenPlus])
        #expect([0, 1, 2, 3, 6, 7, 14].map(MidgarSignalsBuckets.activeDays) == [.none, .oneTwo, .oneTwo, .threeSix, .threeSix, .sevenPlus, .sevenPlus])
        func tenure(_ days: Double) -> MidgarSignal.RenewalOffTenure { MidgarSignalsBuckets.tenure(startedAt: now.addingTimeInterval(-days * 86_400), now: now) }
        #expect([tenure(0), tenure(29), tenure(30), tenure(89), tenure(90), tenure(179), tenure(180), tenure(364), tenure(365)] == [.firstMonth, .firstMonth, .quarter1, .quarter1, .half1, .half1, .year1, .year1, .longer])
    }

    @Test func theContextKeepsFourteenDaysAndTwentyStories() throws {
        var context = MidgarSignalsContext()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0..<30 {
            _ = context.markActive(at: start.addingTimeInterval(Double(offset) * 86_400))
        }
        #expect(context.activeDays.count == 14)
        #expect(context.activeDayCount(at: start.addingTimeInterval(29 * 86_400)) == 14)
        #expect(context.activeDayCount(at: start.addingTimeInterval(36 * 86_400)) == 7)
        #expect(context.markActive(at: start.addingTimeInterval(29 * 86_400)) == false)

        let event = try #require(MidgarSignalEvent(name: "purchase.story", props: [:]))
        for index in 0..<25 {
            context.hold(event, until: start.addingTimeInterval(Double(index)))
        }
        #expect(context.held.count == 20)
        #expect(context.releaseDue(at: start.addingTimeInterval(9)).count == 5)
        #expect(context.held.count == 15)
    }
}
