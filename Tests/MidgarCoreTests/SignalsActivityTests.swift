import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsActivityTests {
    private func periods(in harness: SignalsHarness) -> [String] {
        harness.sentBatches.flatMap { $0 }
            .filter { $0["name"] as? String == "app.active" }
            .compactMap { ($0["props"] as? [String: String])?["period"] }
            .sorted()
    }

    @Test func theFirstActivityOfAnInstallReportsTheDayTheWeekAndTheMonth() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.noteActive()
        await signals.noteActive()
        await signals.flush()

        #expect(periods(in: harness) == ["day", "month", "week"])
    }

    @Test func aLaterDayInTheSameWeekReportsOnlyTheDayAndAnotherInstanceRemembersWhatWasSent() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])
        let first = harness.makeSignals()
        await first.noteActive()
        await first.flush()

        harness.clock.advance(by: 3_600 * 24)
        let relaunched = harness.makeSignals()
        await relaunched.noteActive()
        await relaunched.flush()

        let second = harness.sentBatches.last?.compactMap { ($0["props"] as? [String: String])?["period"] } ?? []
        let sameWeek = MidgarSignals.periodKey(.week, at: harness.clock.now, calendar: MidgarSignals.activityCalendar)
            == MidgarSignals.periodKey(.week, at: harness.clock.now.addingTimeInterval(-3_600 * 24), calendar: MidgarSignals.activityCalendar)
        #expect(second.contains("day"))
        #expect(second.contains("week") == !sameWeek)
    }

    @Test func nothingIsRecordedOrRememberedWhileTheKillSwitchIsOn() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try killedSignalsConfig()
        let signals = harness.makeSignals()
        await signals.noteActive()
        #expect(await signals.pendingCount == 0)

        harness.config.value = MidgarConfig()
        harness.host.enqueue([acceptedReply])
        await signals.noteActive()
        await signals.flush()
        #expect(periods(in: harness) == ["day", "month", "week"])
    }

    @Test func periodsAreNamedByTheISOCalendar() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Helsinki"))
        let sunday = Date(timeIntervalSince1970: 1_792_922_400)
        #expect(MidgarSignals.periodKey(.day, at: sunday, calendar: calendar) == "2026-10-25")
        #expect(MidgarSignals.periodKey(.week, at: sunday, calendar: calendar) == "2026-W43")
        #expect(MidgarSignals.periodKey(.month, at: sunday, calendar: calendar) == "2026-10")
        let monday = sunday.addingTimeInterval(3_600 * 24)
        #expect(MidgarSignals.periodKey(.week, at: monday, calendar: calendar) == "2026-W44")
    }
}
