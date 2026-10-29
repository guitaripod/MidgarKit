import Foundation
import Testing
import MidgarCore
@testable import MidgarUI

@Suite(.serialized) struct SettingsRowTests {
    @Test func versionShowsBuildOnlyWhenItDiffers() {
        #expect(MidgarVersionInfo(name: "Pay Day", version: "1.4.2", build: "87").display == "1.4.2 (87)")
        #expect(MidgarVersionInfo(name: "Pay Day", version: "1.4", build: "1.4").display == "1.4")
        #expect(MidgarVersionInfo(name: "Pay Day", version: "1.4", build: "").display == "1.4")
        #expect(MidgarVersionInfo(name: "Pay Day", version: "", build: "9").display == "9")
    }

    @Test func versionCopyTextIncludesTheName() {
        #expect(MidgarVersionInfo(name: "Pay Day", version: "1.4.2", build: "87").copyText == "Pay Day 1.4.2 (87)")
        #expect(MidgarVersionInfo(name: "", version: "1.0", build: "1").copyText == "1.0 (1)")
    }

    @Test func versionRowCopiesAndShowsVersion() {
        let row = MidgarSettingsRow.version(MidgarVersionInfo(name: "Pay Day", version: "1.4.2", build: "87"))
        #expect(row.detail == "1.4.2 (87)")
        guard case .copy(let text) = row.kind else { Issue.record("expected copy"); return }
        #expect(text == "Pay Day 1.4.2 (87)")
    }

    @Test func supportRowShowsTheAddressAndCopiesIt() {
        let row = MidgarSettingsRow.support(address: "support@midgarcorp.cc")
        #expect(row.detail == "support@midgarcorp.cc")
        guard case .copy(let text) = row.kind else { Issue.record("expected copy"); return }
        #expect(text == "support@midgarcorp.cc")
        #expect(row.menu.map(\.id) == ["midgar.support.copy", "midgar.support.mail"])
    }

    @Test func supportMailIsAConvenienceLink() {
        let row = MidgarSettingsRow.support(address: "support@midgarcorp.cc", subject: "Pay Day 1.4")
        guard case .link(let url) = row.menu.last?.kind else { Issue.record("expected link"); return }
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString == "mailto:support@midgarcorp.cc?subject=Pay%20Day%201.4")
    }

    @Test func blankSupportAddressHasNoMailItem() {
        #expect(MidgarSettingsRow.support(address: "  ").menu.map(\.id) == ["midgar.support.copy"])
    }

    @MainActor @Test func usageCountsRowIsASwitchOnMidgarSignals() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("usage-counts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: "usage-counts-test"), directory: directory)
        let row = MidgarSettingsRow.usageCounts()
        #expect(row.title == "Share anonymous usage counts")
        guard case .toggle(let get, let set) = row.kind else { Issue.record("expected toggle"); return }
        #expect(get())

        set(false)

        #expect(!get())
        #expect(!MidgarSignals.isEnabled)
        set(true)
        #expect(get())
    }

    @Test func usageCountsSectionCarriesAOneLineFooter() {
        let section = MidgarSettingsSection.usageCounts()
        #expect(section.rows.map(\.id) == ["midgar.usageCounts"])
        #expect(section.footer == "Counts only, never anything that identifies you.")
    }

    @Test func legalRowsOpenTheirURLs() throws {
        let privacy = try #require(URL(string: "https://midgarcorp.cc/legal/pay-day/privacy"))
        let terms = try #require(URL(string: "https://midgarcorp.cc/legal/pay-day/terms"))
        guard case .link(let privacyURL) = MidgarSettingsRow.privacyPolicy(url: privacy).kind,
              case .link(let termsURL) = MidgarSettingsRow.termsOfUse(url: terms).kind
        else { Issue.record("expected links"); return }
        #expect(privacyURL == privacy)
        #expect(termsURL == terms)
    }

    @Test @MainActor func deleteAccountIsDestructiveAndConfirmed() {
        let row = MidgarSettingsRow.deleteAccount {}
        #expect(row.role == .destructive)
        #expect(row.confirmation == .deleteAccount)
        #expect(row.confirmation?.confirmTitle == row.title)
    }

    @Test @MainActor func restoreRowAnnouncesSuccess() {
        let row = MidgarSettingsRow.restorePurchases {}
        #expect(row.successMessage == MidgarUIStrings.purchasesRestored)
        #expect(row.role == .standard)
    }

    @Test func standardRowIdentifiersAreUniqueAndNamespaced() throws {
        let url = try #require(URL(string: "https://example.com"))
        let rows: [MidgarSettingsRow] = [
            .restorePurchases {}, .support(address: "a@b.c"), .privacyPolicy(url: url), .termsOfUse(url: url),
            .version(MidgarVersionInfo(name: "A", version: "1", build: "1")), .deleteAccount {}
        ]
        let ids = rows.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("midgar.") })
    }

    @Test func interactivityFollowsKind() {
        #expect(!MidgarSettingsRow.info(id: "a", title: "A", detail: "b").isInteractive)
        #expect(MidgarSettingsRow.custom(id: "a", title: "A") {}.isInteractive)
        #expect(MidgarSettingsRow.support(address: "a@b.c").isInteractive)
    }

    @Test func bundleVersionReadsInfoDictionary() {
        let info = MidgarVersionInfo(bundle: .main)
        #expect(info.version.isEmpty || !info.display.isEmpty)
    }
}

@Suite @MainActor struct SettingsEngineTests {
    private func make() -> (MidgarSettingsEngine, RecordingSystem) {
        let system = RecordingSystem()
        return (MidgarSettingsEngine(system: system), system)
    }

    @Test func copyRowCopiesAndToasts() async {
        let (engine, system) = make()
        await engine.activate(.version(MidgarVersionInfo(name: "A", version: "1", build: "2")))
        #expect(system.copied == ["A 1 (2)"])
        #expect(system.played == [.selection])
        #expect(engine.state.toast?.style == .success)
        #expect(engine.state.toast?.message == MidgarUIStrings.versionCopied)
    }

    @Test func linkRowOpensTheURL() async throws {
        let (engine, system) = make()
        let url = try #require(URL(string: "https://example.com/privacy"))
        await engine.activate(.privacyPolicy(url: url))
        #expect(system.opened == [url])
        #expect(engine.state.failureMessage == nil)
    }

    @Test func linkThatCannotOpenReportsFailure() async throws {
        let (engine, system) = make()
        system.openSucceeds = false
        await engine.activate(.privacyPolicy(url: try #require(URL(string: "https://example.com"))))
        #expect(engine.state.failureMessage == MidgarUIStrings.linkFailed)
        #expect(system.played == [.error])
    }

    @Test func menuItemRunsItsOwnAction() async {
        let (engine, system) = make()
        let row = MidgarSettingsRow.support(address: "a@b.c")
        await engine.activate(row.menu[1])
        #expect(system.opened.map(\.scheme) == ["mailto"])
        await engine.activate(row.menu[0])
        #expect(system.copied == ["a@b.c"])
        #expect(engine.state.toast?.message == MidgarUIStrings.addressCopied)
    }

    @Test func successfulActionToastsItsMessageAndClearsBusy() async {
        let (engine, system) = make()
        var ran = 0
        await engine.activate(.restorePurchases { ran += 1 })
        #expect(ran == 1)
        #expect(engine.state.busyRowIDs.isEmpty)
        #expect(engine.state.toast?.message == MidgarUIStrings.purchasesRestored)
        #expect(system.played == [.success])
    }

    @Test func actionIsBusyWhileItRuns() async {
        let (engine, _) = make()
        var seen: [Set<String>] = []
        engine.onChange = { seen.append($0.busyRowIDs) }
        await engine.activate(.custom(id: "x", title: "X") {})
        #expect(seen.contains(["x"]))
        #expect(engine.state.busyRowIDs.isEmpty)
    }

    @Test func failingActionShowsTheError() async {
        let (engine, system) = make()
        await engine.activate(.restorePurchases { throw TestFailure() })
        #expect(engine.state.failureMessage == "boom")
        #expect(engine.state.toast == nil)
        #expect(system.played == [.error])
        engine.dismissFailure()
        #expect(engine.state.failureMessage == nil)
    }

    @Test func cancelledActionIsSilent() async {
        let (engine, _) = make()
        await engine.activate(.restorePurchases { throw CancellationError() })
        #expect(engine.state.failureMessage == nil)
        #expect(engine.state.busyRowIDs.isEmpty)
    }

    @Test func destructiveActionWaitsForConfirmation() async {
        let (engine, system) = make()
        var deleted = 0
        await engine.activate(.deleteAccount { deleted += 1 })
        #expect(deleted == 0)
        #expect(engine.state.pending?.confirmation == .deleteAccount)
        #expect(system.played == [.warning])
        await engine.confirmPending()
        #expect(deleted == 1)
        #expect(engine.state.pending == nil)
    }

    @Test func cancellingTheConfirmationRunsNothing() async {
        let (engine, _) = make()
        var deleted = 0
        await engine.activate(.deleteAccount { deleted += 1 })
        engine.cancelPending()
        await engine.confirmPending()
        #expect(deleted == 0)
        #expect(engine.state.pending == nil)
    }

    @Test func failedDeletionSurfacesTheError() async {
        let (engine, _) = make()
        await engine.activate(.deleteAccount { throw TestFailure() })
        await engine.confirmPending()
        #expect(engine.state.failureMessage == "boom")
    }

    @Test func toggleWritesThroughAndRefreshes() {
        let (engine, system) = make()
        var value = false
        let row = MidgarSettingsRow.toggle(id: "t", title: "T", isOn: { value }, setOn: { value = $0 })
        let before = engine.state.revision
        engine.setToggle(row, to: true)
        #expect(value)
        #expect(engine.state.revision == before + 1)
        #expect(system.played == [.selection])
    }

    @Test func infoRowDoesNothing() async {
        let (engine, system) = make()
        await engine.activate(.info(id: "i", title: "I", detail: "d"))
        #expect(system.copied.isEmpty && system.opened.isEmpty && system.played.isEmpty)
        #expect(engine.state.toast == nil)
    }

    @Test func onChangeSeesEveryTransition() async {
        let (engine, _) = make()
        var count = 0
        engine.onChange = { _ in count += 1 }
        await engine.activate(.restorePurchases {})
        #expect(count >= 3)
    }

    @Test func confirmingRunsTheHandlerEvenWhenTheAlertDismissalCancelsFirst() async {
        let (engine, _) = make()
        var deleted = 0
        await engine.activate(.deleteAccount { deleted += 1 })

        let running = engine.beginConfirmedAction()
        engine.cancelPending()
        await running?.value

        #expect(deleted == 1)
        #expect(engine.state.pending == nil)
        #expect(engine.state.busyRowIDs.isEmpty)
    }

    @Test func aDismissalWithoutAButtonRunsNothing() async {
        let (engine, _) = make()
        var deleted = 0
        await engine.activate(.deleteAccount { deleted += 1 })

        engine.cancelPending()
        let running = engine.beginConfirmedAction()

        #expect(running == nil)
        #expect(deleted == 0)
    }

    @Test func confirmingTwiceRunsTheHandlerOnce() async {
        let (engine, _) = make()
        var deleted = 0
        await engine.activate(.deleteAccount { deleted += 1 })

        let first = engine.beginConfirmedAction()
        let second = engine.beginConfirmedAction()
        await first?.value
        await second?.value

        #expect(deleted == 1)
        #expect(second == nil)
    }

    @Test func theSwiftUIModelRepublishesTheEngineStateAndLetsBothGo() {
        weak var weakModel: MidgarSettingsModel?
        weak var weakEngine: MidgarSettingsEngine?
        do {
            let model = MidgarSettingsModel(engine: MidgarSettingsEngine(system: RecordingSystem()))
            weakModel = model
            weakEngine = model.engine
            var value = false
            let row = MidgarSettingsRow.toggle(id: "t", title: "T", isOn: { value }, setOn: { value = $0 })
            let before = model.state.revision
            model.engine.setToggle(row, to: true)
            #expect(model.state.revision == before + 1)
        }
        #expect(weakModel == nil)
        #expect(weakEngine == nil)
    }
}
