import Foundation
import Testing
@testable import MidgarCommerce
@testable import MidgarCommerceUI

@Suite struct TrialTimelineTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let start = Date(timeIntervalSince1970: 1_767_268_800)

    private func steps(_ offer: MidgarIntroOffer, reminder: Bool = true) -> MidgarTrialTimelineSteps? {
        MidgarTrialTimelineSteps(
            presentation: PlanFixtures.trial("p", offer: offer),
            start: Self.start,
            includesReminder: reminder,
            calendar: Self.calendar,
            locale: PlanFixtures.english
        )
    }

    private func offer(_ value: Int, _ unit: MidgarPeriodUnit, count: Int = 1, kind: MidgarIntroOffer.Kind = .freeTrial) -> MidgarIntroOffer {
        MidgarIntroOffer(kind: kind, period: MidgarBillingPeriod(value: value, unit: unit), periodCount: count, displayPrice: "$0.00")
    }

    @Test func aWeekLongTrialHasTodayTheReminderAndTheChargeDay() throws {
        let timeline = try #require(steps(offer(1, .week)))

        #expect(timeline.steps.map(\.kind) == [.today, .reminder, .charge])
        #expect(timeline.steps.map(\.title) == ["Today", "Jan 6", "Jan 8"])
        #expect(timeline.steps.map(\.symbol) == ["lock.open.fill", "bell.fill", "star.fill"])
        #expect(timeline.steps[2].detail.contains("$39.99/year"))
        #expect(timeline.endsAt == Self.start.addingTimeInterval(7 * 86_400))
    }

    @Test func aShortTrialRemindsOneDayAheadAndAOneDayTrialHasNoRoomForAReminder() throws {
        let threeDays = try #require(steps(offer(3, .day)))
        let oneDay = try #require(steps(offer(1, .day)))

        #expect(threeDays.steps.map(\.title) == ["Today", "Jan 3", "Jan 4"])
        #expect(oneDay.steps.map(\.kind) == [.today, .charge])
    }

    @Test func theTimelineFollowsTheOfferPeriodAndPeriodCount() throws {
        let month = try #require(steps(offer(1, .month)))
        let twoWeeks = try #require(steps(offer(1, .week, count: 2)))

        #expect(month.steps.last?.title == "Feb 1")
        #expect(twoWeeks.steps.last?.title == "Jan 15")
    }

    @Test func anAppThatPostsNoReminderGetsNoReminderStep() throws {
        let timeline = try #require(steps(offer(1, .week), reminder: false))

        #expect(timeline.steps.map(\.kind) == [.today, .charge])
    }

    @Test func aPaidIntroductoryOfferHasNoFreeTrialTimeline() {
        #expect(steps(offer(1, .month, kind: .payAsYouGo)) == nil)
        #expect(steps(offer(1, .month, kind: .payUpFront)) == nil)
    }

    @Test func theReminderLeadIsTwoDaysFromFiveDaysAndOneDayBefore() {
        let end = Self.start.addingTimeInterval(5 * 86_400)

        #expect(MidgarTrialTimelineSteps.reminderDate(start: Self.start, end: end) == end.addingTimeInterval(-2 * 86_400))
        #expect(MidgarTrialTimelineSteps.reminderDate(start: Self.start, end: Self.start.addingTimeInterval(4 * 86_400)) == Self.start.addingTimeInterval(3 * 86_400))
        #expect(MidgarTrialTimelineSteps.reminderDate(start: Self.start, end: Self.start.addingTimeInterval(86_400)) == nil)
    }

    @Test func theTimelineAppearsOnlyForThePlanWhoseTrialTheCustomerMayUse() throws {
        let eligible = PlanFixtures.catalog()
        let used = PlanFixtures.catalog(presentations: [:])

        #expect(eligible.plan(id: PlanFixtures.yearly)?.trial != nil)
        #expect(eligible.plan(id: PlanFixtures.monthly)?.trial == nil)
        #expect(eligible.plan(id: PlanFixtures.lifetime)?.trial == nil)
        #expect(used.plans.allSatisfy { $0.trial == nil })
    }
}
