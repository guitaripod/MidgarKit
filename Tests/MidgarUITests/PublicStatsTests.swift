import Foundation
import Testing
@testable import MidgarUI

@Suite struct PublicStatsTests {
    @Test func decodesTheShapeOfTheLivePublicAnswer() throws {
        let stats = try decodePublicStats()

        #expect(Set(stats.apps.keys) == ["dream-eater", "flaccy"])
        #expect(stats.minimumCount == 10)
        #expect(stats.apps["flaccy"]?.weeks.count == 2)
    }

    @Test func theLatestFinishedWeekOfTheAppIsTheOneShown() throws {
        let numbers = try #require(try decodePublicStats().latestWeek(for: "flaccy"))

        #expect(numbers.weekStarting == "2026-10-19")
        #expect(numbers.weeklyActiveInstalls == .exactly(12))
        #expect(numbers.newInstalls == .fewerThan(10))
    }

    @Test func theLatestWeekIsFoundByItsDateNotByItsPlace() throws {
        let json = publicStatsJSON.replacingOccurrences(of: "\"apps\": {", with: "\"apps\": { \"shuffled\": { \"weeks\": [{ \"period\": \"2026-10-19\", \"wau\": 40, \"new_installs\": 15 }, { \"period\": \"2026-10-12\", \"wau\": 1, \"new_installs\": 1 }] },")
        let numbers = try #require(try decodePublicStats(json).latestWeek(for: "shuffled"))

        #expect(numbers.weekStarting == "2026-10-19")
        #expect(numbers.weeklyActiveInstalls == .exactly(40))
        #expect(numbers.newInstalls == .exactly(15))
    }

    @Test func aHiddenFigureReadsFewerThanTen() throws {
        let numbers = try #require(try decodePublicStats().latestWeek(for: "dream-eater"))

        #expect(numbers.weeklyActiveInstalls == .fewerThan(10))
        #expect(numbers.weeklyActiveInstalls?.display == "fewer than 10")
        #expect(numbers.newInstalls?.display == "fewer than 10")
    }

    @Test func aRealFigureIsShownAsAGroupedNumber() {
        #expect(MidgarPublicStats.Count.exactly(12).display == "12")
        #expect(MidgarPublicStats.Count.exactly(1234).display == 1234.formatted(.number))
    }

    @Test func aFigureUnderTheMinimumNeverReachesTheScreen() throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": 3, "new_installs": 0 }] } } }"#
        let numbers = try #require(try decodePublicStats(json).latestWeek(for: "a"))

        #expect(numbers.weeklyActiveInstalls == .fewerThan(10))
        #expect(numbers.newInstalls == .fewerThan(10))
    }

    @Test func theMinimumFollowsTheServersRule() throws {
        let json = #"{ "rules": { "min_count": 20 }, "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": 12, "new_installs": "<20" }] } } }"#
        let numbers = try #require(try decodePublicStats(json).latestWeek(for: "a"))

        #expect(numbers.weeklyActiveInstalls == .fewerThan(20))
        #expect(numbers.newInstalls?.display == "fewer than 20")
    }

    @Test func aMissingRulesBlockMeansTheDefaultMinimum() throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": 4 }] } } }"#

        #expect(try decodePublicStats(json).latestWeek(for: "a")?.weeklyActiveInstalls == .fewerThan(10))
    }

    @Test func aFigureInAShapeThisVersionDoesNotKnowIsLeftOut() throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": null, "new_installs": ["x"] }] }, "b": { "weeks": [{ "period": "2026-10-19", "wau": { "n": 1 }, "new_installs": 25 }] } } }"#
        let stats = try decodePublicStats(json)

        #expect(stats.latestWeek(for: "a") == nil)
        #expect(stats.latestWeek(for: "b")?.weeklyActiveInstalls == nil)
        #expect(stats.latestWeek(for: "b")?.newInstalls == .exactly(25))
    }

    @Test func aNegativeOrOddlyWrittenFigureIsNotACount() throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": -4, "new_installs": "many" }] }, "b": { "weeks": [{ "period": "2026-10-19", "wau": "<0", "new_installs": "<x" }] } } }"#
        let stats = try decodePublicStats(json)

        #expect(stats.latestWeek(for: "a") == nil)
        #expect(stats.latestWeek(for: "b") == nil)
    }

    @Test func aWholeNumberWrittenWithADecimalPointIsStillACount() throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": 25.0, "new_installs": 18.4 }] } } }"#
        let numbers = try #require(try decodePublicStats(json).latestWeek(for: "a"))

        #expect(numbers.weeklyActiveInstalls == .exactly(25))
        #expect(numbers.newInstalls == .exactly(18))
    }

    @Test func oneUnreadableAppDoesNotTakeTheOthersDown() throws {
        let json = #"{ "apps": { "broken": { "weeks": "none" }, "worse": 7, "fine": { "weeks": [{ "period": "2026-10-19", "wau": 30 }] } } }"#
        let stats = try decodePublicStats(json)

        #expect(stats.latestWeek(for: "fine")?.weeklyActiveInstalls == .exactly(30))
        #expect(stats.latestWeek(for: "broken") == nil)
        #expect(stats.latestWeek(for: "worse") == nil)
    }

    @Test func thereIsNothingToShowForAnAppTheAnswerLeavesOut() throws {
        let stats = try decodePublicStats()

        #expect(stats.latestWeek(for: "psywave") == nil)
        #expect(stats.latestWeek(for: "") == nil)
        #expect(try decodePublicStats(#"{ "apps": { "a": { "weeks": [] } } }"#).latestWeek(for: "a") == nil)
    }

    @Test func anAnswerWithoutAppsIsNotAnAnswer() {
        #expect(throws: DecodingError.self) { try decodePublicStats("{}") }
        #expect(throws: DecodingError.self) { try decodePublicStats("[]") }
    }

    @Test func theWeekStartsOnTheDateTheServerNamedWhateverTheTimeZone() throws {
        let start = try #require(MidgarAppNumbers.date(from: "2026-10-19"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: start)

        #expect((parts.year, parts.month, parts.day, parts.hour) == (2026, 10, 19, 0))
        let numbers = MidgarAppNumbers(weekStarting: "2026-10-19", weeklyActiveInstalls: nil, newInstalls: .exactly(30))
        #expect(numbers.weekStartingDisplay.contains("19"))
        #expect(numbers.weekStartingDisplay.contains("2026"))
    }

    @Test func aPeriodThatIsNotADateIsShownAsItIs() {
        #expect(MidgarAppNumbers.date(from: "next week") == nil)
        #expect(MidgarAppNumbers(weekStarting: "next week", weeklyActiveInstalls: .exactly(12), newInstalls: nil).weekStartingDisplay == "next week")
    }
}
