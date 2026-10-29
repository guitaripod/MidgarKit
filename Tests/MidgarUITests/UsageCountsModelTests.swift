import Foundation
import Testing
import MidgarCore
@testable import MidgarUI

@Suite @MainActor struct UsageCountsModelTests {
    private func model(
        appID: String? = "flaccy",
        catalog: [MidgarSignalCatalog.Entry] = fixtureCatalog,
        switchRow: MidgarSettingsRow = FakeSwitch().row,
        loader: any MidgarPublicStatsLoading
    ) -> MidgarUsageCountsModel {
        MidgarUsageCountsModel(appID: appID, catalog: catalog, switchRow: switchRow, loader: loader)
    }

    private func answering() throws -> FakeStatsLoader {
        FakeStatsLoader(.stats(try decodePublicStats()))
    }

    private func ids(_ model: MidgarUsageCountsModel) -> [String] {
        model.sections.map(\.id)
    }

    @Test func theScreenListsTheSwitchWhatTheAppSendsItsNumbersAndTheLinkInThatOrder() async throws {
        let model = model(loader: try answering())
        await model.load()

        #expect(ids(model) == ["midgar.usageCounts.switch", "midgar.usageCounts.events", "midgar.usageCounts.numbers", "midgar.usageCounts.all"])
        #expect(model.sections.map(\.title) == [nil, "What this app sends", "This app's numbers", nil])
    }

    @Test func theNumbersAreLeftOutUntilTheyHaveBeenRead() throws {
        let model = model(loader: try answering())

        #expect(ids(model) == ["midgar.usageCounts.switch", "midgar.usageCounts.events", "midgar.usageCounts.all"])
    }

    @Test func theNumbersSectionIsLeftOutWhenTheFetchFails() async {
        let loader = FakeStatsLoader(.failure(URLError(.timedOut)))
        let model = model(loader: loader)

        await model.load()

        #expect(model.numbers == nil)
        #expect(ids(model) == ["midgar.usageCounts.switch", "midgar.usageCounts.events", "midgar.usageCounts.all"])
    }

    @Test func aFailedFetchIsNotRetriedWhileTheScreenIsOpen() async {
        let loader = FakeStatsLoader(.failure(MidgarPublicStatsError.status(503)))
        let model = model(loader: loader)

        await model.load()
        await model.load()
        await model.load()

        #expect(await loader.requests == 1)
    }

    @Test func aSuccessfulFetchIsNotRepeatedEither() async throws {
        let loader = try answering()
        let model = model(loader: loader)

        await model.load()
        await model.load()

        #expect(await loader.requests == 1)
        #expect(model.numbers?.weekStarting == "2026-10-19")
    }

    @Test func theNumbersSectionIsLeftOutWhenTheAnswerHasNothingForThisApp() async throws {
        let model = model(appID: "psywave", loader: try answering())

        await model.load()

        #expect(model.numbers == nil)
        #expect(!ids(model).contains("midgar.usageCounts.numbers"))
    }

    @Test func anAppWithoutASlugAsksForNothingAndShowsNoNumbers() async throws {
        let loader = try answering()
        let model = model(appID: nil, loader: loader)

        await model.load()

        #expect(await loader.requests == 0)
        #expect(!ids(model).contains("midgar.usageCounts.numbers"))
    }

    @Test func aLoadThatWasCancelledMayBeTriedAgain() async throws {
        let loader = FakeStatsLoader(.neverAnswers)
        let model = model(loader: loader)

        let first = Task { await model.load() }
        while await loader.requests == 0 { await Task.yield() }
        first.cancel()
        await first.value
        let second = Task { await model.load() }
        while await loader.requests < 2 { await Task.yield() }
        second.cancel()
        await second.value

        #expect(await loader.requests == 2)
        #expect(model.numbers == nil)
    }

    @Test func theNumbersRowsShowTheCountsAndFewerThanTen() async throws {
        let model = model(loader: try answering())
        await model.load()

        let section = try #require(model.sections.first { $0.id == "midgar.usageCounts.numbers" })

        #expect(section.rows.map(\.title) == ["Weekly active installs", "New installs"])
        #expect(section.rows.map(\.detail) == ["12", "fewer than 10"])
        #expect(try #require(section.footer).contains("Finished week starting"))
        #expect(try #require(section.footer).contains("2026"))
    }

    @Test func aHiddenWeekStillShowsBothFiguresAsFewerThanTen() async throws {
        let model = model(appID: "dream-eater", loader: try answering())
        await model.load()

        let section = try #require(model.sections.first { $0.id == "midgar.usageCounts.numbers" })

        #expect(section.rows.map(\.detail) == ["fewer than 10", "fewer than 10"])
    }

    @Test func aWeekWithOnlyOneFigureShowsOneRow() async throws {
        let json = #"{ "apps": { "a": { "weeks": [{ "period": "2026-10-19", "wau": 30 }] } } }"#
        let model = model(appID: "a", loader: FakeStatsLoader(.stats(try decodePublicStats(json))))
        await model.load()

        let section = try #require(model.sections.first { $0.id == "midgar.usageCounts.numbers" })

        #expect(section.rows.map(\.title) == ["Weekly active installs"])
    }

    @Test func theEventsAreTheOnesTheAppMaySendAndNeverTheReservedOnes() {
        let alpha = model(appID: "alpha", loader: FakeStatsLoader(.neverAnswers))
        let beta = model(appID: "beta", loader: FakeStatsLoader(.neverAnswers))
        let nobody = model(appID: nil, loader: FakeStatsLoader(.neverAnswers))

        #expect(alpha.events.map(\.name) == ["fixture.active", "fixture.view", "fixture.alpha"])
        #expect(beta.events.map(\.name) == ["fixture.active", "fixture.view", "fixture.beta"])
        #expect(nobody.events.map(\.name) == ["fixture.active", "fixture.view"])
    }

    @Test func anEventRowGivesItsPurposeHowOftenItIsSentAndTheInstallWeek() throws {
        let model = model(loader: FakeStatsLoader(.neverAnswers))
        let rows = try #require(model.sections.first { $0.id == "midgar.usageCounts.events" }).rows

        #expect(rows.map(\.title) == [
            "Daily, weekly and monthly active installs.",
            "How often the purchase screen is shown, and from where in the app."
        ])
        #expect(rows[0].subtitle == "Sent at most once a day, once a week and once a month\nIncludes the week this app was installed")
        #expect(rows[1].subtitle == "Sent every time it happens")
        #expect(rows.allSatisfy { !$0.isInteractive })
    }

    @Test func everyKindOfFrequencyHasItsOwnWords() {
        let words = MidgarSignal.Uniqueness.allCases.map(MidgarUIStrings.frequency(of:))

        #expect(Set(words).count == MidgarSignal.Uniqueness.allCases.count)
        #expect(MidgarUIStrings.frequency(of: .daily) == "Sent at most once a day")
        #expect(MidgarUIStrings.frequency(of: .weekly) == "Sent at most once a week")
        #expect(MidgarUIStrings.frequency(of: .monthly) == "Sent at most once a month")
        #expect(MidgarUIStrings.frequency(of: .lifetime) == "Sent only the first time it happens")
    }

    @Test func theGeneratedCatalogGivesEveryEventAReadableLine() {
        let model = MidgarUsageCountsModel(appID: "flaccy", loader: FakeStatsLoader(.neverAnswers))
        let rows = model.sections.first { $0.id == "midgar.usageCounts.events" }?.rows ?? []

        #expect(rows.count == MidgarSignalCatalog.entries(for: "flaccy").count)
        #expect(rows.count > 0)
        #expect(rows.allSatisfy { !$0.title.isEmpty && ($0.subtitle ?? "").hasPrefix("Sent") })
    }

    @Test func theSwitchIsTheUsageCountsSwitch() throws {
        let model = MidgarUsageCountsModel(appID: "flaccy", loader: FakeStatsLoader(.neverAnswers))
        let row = try #require(model.sections.first?.rows.first)

        #expect(row.id == MidgarSettingsRow.usageCounts().id)
        #expect(row.title == MidgarSettingsRow.usageCounts().title)
        guard case .toggle = row.kind else { Issue.record("expected toggle"); return }
        #expect(model.sections.first?.footer == "Turning this off stops the app from sending counts and deletes any that are waiting.")
    }

    @Test func flippingTheSwitchTellsTheListWhetherAnythingIsSent() throws {
        let fake = FakeSwitch(isOn: true)
        let model = model(switchRow: fake.row, loader: FakeStatsLoader(.neverAnswers))
        let events = { model.sections.first { $0.id == "midgar.usageCounts.events" } }
        #expect(events()?.footer == nil)
        #expect(model.isEnabled)

        let set = try #require(model.sections.first?.toggleSetter())
        set(false)

        #expect(!fake.isOn)
        #expect(!model.isEnabled)
        #expect(events()?.footer == "Counts are turned off, so none of these are sent.")
        set(true)
        #expect(fake.isOn)
        #expect(events()?.footer == nil)
    }

    @Test func theLinkOpensAllOfMidgarsNumbers() throws {
        let model = model(loader: FakeStatsLoader(.neverAnswers))
        let row = try #require(model.sections.last?.rows.first)

        #expect(row.title == "All of Midgar's numbers")
        guard case .link(let url) = row.kind else { Issue.record("expected link"); return }
        #expect(url.absoluteString == "https://midgarcorp.cc/open")
    }

    @Test func theIntroSaysCountsNotPeople() {
        #expect(MidgarUIStrings.usageCountsIntro == "Usage counts are counts, not people. Nothing in them identifies your device or you, and small numbers are never shown.")
    }
}
