import Foundation
import Testing
@testable import MidgarCore

/// The events of Lifestream 3 stay inside the apps whose registry entry has a `[lifestream]` table.
@Suite struct SignalsAdoptionTests {
    private static let notAdopted = "crucible"

    private func experiment() throws -> MidgarConfig {
        let json = #"{"app":"crucible","version":9,"values":{"lab.paywall-headline":"control,outcome;paywall.view;paywall.purchase"}}"#
        return MidgarConfig(document: try JSONDecoder().decode(MidgarConfigDocument.self, from: Data(json.utf8)), defaults: [:])
    }

    @Test func theRegistryNamesTheAdoptersOnTheNewEventsAndNobodyElseOnTheOldOnes() throws {
        let tier = try #require(MidgarSignalCatalog.entry(named: "app.tier"))
        #expect(tier.isAdoptedOnly && tier.apps.contains("dream-eater") && !tier.apps.contains(Self.notAdopted))
        let view = try #require(MidgarSignalCatalog.entry(named: "paywall.view"))
        #expect(!view.isAdoptedOnly && view.isAllowed(for: Self.notAdopted))
        #expect(MidgarSignalCatalog.Entry(name: "x", purpose: "x", uniqueness: .each, isAdoptedOnly: true).isAllowed(for: "dream-eater") == false)
    }

    @Test func anAppThatHasNotAdoptedSendsWhatItSentBeforeAndNothingNew() async throws {
        let harness = SignalsHarness(appID: Self.notAdopted)
        defer { harness.cleanUp() }
        harness.config.value = try experiment()
        var policy = MidgarSignalsPolicy.standard
        policy.storyDelay = 0...0
        let signals = harness.makeSignals(policy: policy)

        #expect(!signals.hasAdopted)
        #expect(!signals.sendsCrashReports)
        #expect(signals.variant(of: "paywall-headline") == nil)

        await signals.noteActive()
        await signals.note(.tier(.paid))
        await signals.send(.featureUse(feature: "quiz"))
        await signals.noteValue()
        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        await signals.note(.purchased)
        await signals.note(.renewalOff(startedAt: harness.clock.now.addingTimeInterval(-86_400)))
        await signals.send(.healthCrashed(kind: .crash))
        await signals.send(.errorHit(domain: .network, code: .offline))
        harness.clock.advance(by: 60)

        let names = Set(await harness.drain(signals).map(\.name))
        #expect(names == ["app.active", "paywall.view", "paywall.purchase"])
    }

    @Test func anAdopterSendsThem() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        #expect(signals.hasAdopted)
        #expect(signals.sendsCrashReports)
        await signals.note(.tier(.paid))
        await signals.send(.healthCrashed(kind: .crash))
        #expect(Set(await harness.drain(signals).map(\.name)) == ["app.tier", "health.crashed"])

        signals.setEnabled(false)
        #expect(!signals.sendsCrashReports)
    }

    @Test func theDayTheLastCrashReportLeftIsKeptForTheScreen() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        #expect(signals.lastCrashReportDay == nil)

        var state = MidgarDiagnosticsState()
        state.lastSent = "2026-11-20"
        signals.diagnosticsStore.save(state)
        #expect(signals.lastCrashReportDay == "2026-11-20")
    }
}
