import Foundation
import Testing
import MidgarCore
@testable import MidgarUI

extension SettingsRowTests {
    @MainActor @Test func usageCountsDetailShowsOnAndOffAsTheSwitchChanges() {
        let fake = FakeSwitch(isOn: true)
        let row = MidgarSettingsRow.usageCountsDetail(isEnabled: { fake.isOn }, perform: {})

        #expect(row.id == "midgar.usageCountsDetail")
        #expect(row.title == "Usage Counts")
        #expect(row.currentDetail == "On")
        fake.isOn = false
        #expect(row.currentDetail == "Off")
        fake.isOn = true
        #expect(row.currentDetail == "On")
    }

    @MainActor @Test func usageCountsDetailOpensTheScreenThroughItsHandler() async {
        let opened = OpenCounter()
        let row = MidgarSettingsRow.usageCountsDetail(isEnabled: { true }, perform: { opened.count += 1 })
        let engine = MidgarSettingsEngine(system: RecordingSystem())

        await engine.activate(row)

        #expect(opened.count == 1)
        #expect(row.showsDisclosure)
        #expect(row.isInteractive)
        #expect(row.systemImage == "chart.bar")
    }

    @MainActor @Test func aRowWithoutAProviderShowsItsPlainDetail() {
        let plain = MidgarSettingsRow.info(id: "x", title: "Version", detail: "1.0")

        #expect(plain.currentDetail == "1.0")
        #expect(MidgarSettingsRow(id: "y", title: "Nothing").currentDetail == nil)
    }

    @MainActor @Test func theEngineRedrawsTheRowsWhenAskedTo() {
        let engine = MidgarSettingsEngine(system: RecordingSystem())
        let before = engine.state.revision

        engine.refresh()

        #expect(engine.state.revision == before + 1)
    }

    @MainActor @Test func theDetailRowFollowsMidgarSignalsAndTheSwitchRowStaysASwitch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-counts-detail-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: "usage-counts-detail-test"), directory: directory)
        let detail = MidgarSettingsRow.usageCountsDetail {}
        let model = MidgarUsageCountsModel(loader: FakeStatsLoader(.neverAnswers))

        #expect(MidgarSignals.appID == "usage-counts-detail-test")
        #expect(model.appID == "usage-counts-detail-test")
        #expect(detail.currentDetail == "On")
        #expect(model.isEnabled)
        let set = try #require(model.sections.first?.toggleSetter())

        set(false)

        #expect(!MidgarSignals.isEnabled)
        #expect(!model.isEnabled)
        #expect(detail.currentDetail == "Off")
        set(true)
        #expect(MidgarSignals.isEnabled)
        #expect(detail.currentDetail == "On")
        guard case .toggle = MidgarSettingsRow.usageCounts().kind else { Issue.record("usageCounts() must stay a switch"); return }
    }
}

@MainActor
final class OpenCounter {
    var count = 0
}
