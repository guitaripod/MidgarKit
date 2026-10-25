import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsCohortTests {
    private func cohort(_ sent: [(name: String, props: [String: Any])], _ name: String) -> String? {
        sent.first { $0.name == name }?.props["cohort"] as? String
    }

    @Test func aCohortEventCarriesTheISOWeekOfTheFirstLaunch() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        let week = MidgarSignals.periodKey(.week, at: harness.clock.now, calendar: MidgarSignals.activityCalendar)

        await signals.send(.funnelStep(step: .samplePlayed))
        await signals.send(.paywallView(placement: .paywall))
        let sent = await harness.drain(signals)

        #expect(cohort(sent, "funnel.step") == week)
        #expect(week.range(of: #"^\d{4}-W\d{2}$"#, options: .regularExpression) != nil)
        #expect(sent.first { $0.name == "paywall.view" }?.props["cohort"] == nil)
    }

    @Test func theCohortIsDecidedOnceAndSurvivesLaterWeeksAndRelaunches() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let first = harness.makeSignals()
        let week = MidgarSignals.periodKey(.week, at: harness.clock.now, calendar: MidgarSignals.activityCalendar)
        await first.send(.funnelStep(step: .samplePlayed))
        #expect(harness.storedCohort == week)

        harness.advance(toNext: .weekOfYear)
        harness.advance(toNext: .weekOfYear)
        let relaunched = harness.makeSignals()
        await relaunched.send(.funnelStep(step: .libraryFilled))
        let sent = await harness.drain(relaunched)

        #expect(cohort(sent, "funnel.step") == week)
    }

    @Test func anAppThatSaysTheInstallPredatesLifestreamGetsLegacy() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(existingInstall: true)

        await signals.noteActive()
        let sent = await harness.drain(signals)

        #expect(sent.count == 3)
        #expect(sent.allSatisfy { $0.props["cohort"] as? String == "legacy" })
    }

    @Test func legacyIsKeptWhenALaterLaunchStopsSayingSo() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        await harness.makeSignals(existingInstall: true).send(.funnelStep(step: .samplePlayed))

        let later = harness.makeSignals(existingInstall: false)
        await later.send(.funnelStep(step: .trialStarted))
        let sent = await harness.drain(later)

        #expect(sent.allSatisfy { $0.props["cohort"] as? String == "legacy" })
    }

    @Test func aFreshInstallIsNotLegacyEvenWhenItSaysSoNever() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.send(.appActive(period: .day))
        let sent = await harness.drain(signals)

        #expect(cohort(sent, "app.active") != "legacy")
    }

    @Test func anInstallThatAlreadyReportedActivityBeforeThisCodeIsLegacyAndKeepsItsPeriods() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let store = MidgarSignalsStore(directory: harness.directory, appID: harness.appID)
        let keys = MidgarSignalPeriodKeys(at: harness.clock.now)
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(["day": keys.day, "week": keys.week, "month": keys.month]).write(to: store.sibling("activity"))
        let signals = harness.makeSignals()

        await signals.noteActive()
        #expect(await signals.pendingCount == 0)

        harness.advance(toNext: .day)
        await signals.noteActive()
        let sent = await harness.drain(signals)

        #expect(sent.contains { $0.props["period"] as? String == "day" })
        #expect(sent.allSatisfy { $0.props["cohort"] as? String == "legacy" })
        #expect(!FileManager.default.fileExists(atPath: store.sibling("activity").path))
    }
}
