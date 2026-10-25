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

    private func week(_ date: Date) -> String {
        MidgarSignals.periodKey(.week, at: date, calendar: MidgarSignals.activityCalendar)
    }

    @Test func anInstallFromAnEarlierWeekIsInThatWeeksCohort() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let installed = harness.clock.now.addingTimeInterval(-3_600 * 24 * 40)
        let signals = harness.makeSignals(installDate: { installed })

        await signals.noteActive()
        let sent = await harness.drain(signals)

        #expect(sent.count == 3)
        #expect(sent.allSatisfy { $0.props["cohort"] as? String == week(installed) })
        #expect(week(installed) != week(harness.clock.now))
    }

    @Test func aDateInTheFutureIsClampedToNow() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(installDate: { harness.clock.now.addingTimeInterval(3_600 * 24 * 90) })

        await signals.send(.funnelStep(step: .samplePlayed))
        let sent = await harness.drain(signals)

        #expect(cohort(sent, "funnel.step") == week(harness.clock.now))
    }

    @Test func anInstallDateThatCannotBeReadFallsBackToTheWeekOfTheFirstLaunch() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(installDate: { nil })

        await signals.send(.funnelStep(step: .samplePlayed))
        let sent = await harness.drain(signals)

        #expect(cohort(sent, "funnel.step") == week(harness.clock.now))
    }

    @Test func aDateBefore2020IsLegacy() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals(installDate: { Date(timeIntervalSince1970: 1_500_000_000) })

        await signals.noteActive()
        let sent = await harness.drain(signals)

        #expect(sent.count == 3)
        #expect(sent.allSatisfy { $0.props["cohort"] as? String == "legacy" })
    }

    @Test func theCohortNeverMovesOnceItIsPersisted() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let installed = harness.clock.now.addingTimeInterval(-3_600 * 24 * 40)
        await harness.makeSignals(installDate: { installed }).send(.funnelStep(step: .samplePlayed))
        #expect(harness.storedCohort == week(installed))

        let relaunched = harness.makeSignals(installDate: { harness.clock.now })
        await relaunched.send(.funnelStep(step: .trialStarted))
        let sent = await harness.drain(relaunched)

        #expect(cohort(sent, "funnel.step") == week(installed))
    }

    @Test func theInstallDateComesFromTheCreationDateOfTheFolder() throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: past], ofItemAtPath: harness.directory.path)

        let read = MidgarSignalsInstallDate.creationDate(of: harness.directory, fileManager: .default)

        #expect(read == past)
        #expect(MidgarSignalsInstallDate.creationDate(of: harness.directory.appendingPathComponent("missing"), fileManager: .default) == nil)
        #expect(MidgarSignalsInstallDate.creationDate(of: nil, fileManager: .default) == nil)
    }
}
