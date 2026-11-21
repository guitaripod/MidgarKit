import Foundation
import Testing
@testable import MidgarCore

/// Experiments: the device picks the version, and exposure and outcome leave as counts.
@Suite struct SignalsLabTests {
    private static let headline = "paywall-headline-2026-12"

    private func running(_ experiments: [String: String]) throws -> MidgarConfig {
        let values = try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: experiments.map { ("lab." + $0.key, $0.value) }))
        let json = #"{"app":"dream-eater","version":9,"values":"# + String(decoding: values, as: UTF8.self) + "}"
        return MidgarConfig(document: try JSONDecoder().decode(MidgarConfigDocument.self, from: Data(json.utf8)), defaults: [:])
    }

    private func labEvents(_ sent: [(name: String, props: [String: Any])]) -> [String] {
        sent.filter { $0.name.hasPrefix("lab.") }.map { "\($0.name) \($0.props["experiment"] ?? "-") \($0.props["variant"] ?? "-")" }
    }

    @Test func anExperimentIsReadFromItsConfigValueAndAMalformedOneRunsNothing() throws {
        let experiment = try #require(MidgarExperiment(id: "x", value: "control,outcome;paywall.view;paywall.purchase"))
        #expect(experiment.variants == ["control", "outcome"])
        #expect(experiment.exposed == "paywall.view")
        #expect(experiment.converted == "paywall.purchase")
        for broken in ["", "control;paywall.view;paywall.purchase", "control,control;a;b", "control,outcome;a", "control,outcome;a;a", "control,outcome;;b", "control,outcome;a;b;c"] {
            #expect(MidgarExperiment(id: "x", value: broken) == nil, "\(broken)")
        }
        #expect(MidgarExperiment(id: "", value: "control,outcome;a;b") == nil)
    }

    @Test func aSeedAlwaysPicksTheSameVersionAndSeedsSpreadOverTheVersions() throws {
        let experiment = try #require(MidgarExperiment(id: Self.headline, value: "control,outcome;paywall.view;paywall.purchase"))
        let other = try #require(MidgarExperiment(id: "onboarding-order-2027-01", value: "control,short;app.active;funnel.step"))
        #expect(experiment.variant(seed: 42) == experiment.variant(seed: 42))

        let picks = (0..<2_000).map { experiment.variant(seed: UInt64($0) &* 0x9E37_79B9_7F4A_7C15) }
        let share = Double(picks.filter { $0 == "outcome" }.count) / 2_000
        #expect((0.45...0.55).contains(share))

        let both = (0..<2_000).filter { experiment.variant(seed: UInt64($0)) == "outcome" && other.variant(seed: UInt64($0)) == "short" }.count
        #expect((400...600).contains(both), "two experiments split an install independently")
    }

    @Test func noExperimentInTheConfigMeansNoVersionAndNoLabEvent() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        #expect(signals.variant(of: Self.headline) == nil)
        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        #expect(labEvents(await harness.drain(signals)).isEmpty)
    }

    @Test func theFirstExposureEntersTheInstallAndAnOutcomeCountsOnlyAfterIt() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals()
        let variant = try #require(signals.variant(of: Self.headline))
        #expect(["control", "outcome"].contains(variant))

        await signals.send(.paywallPurchase(product: "com.example.pro"))
        #expect(labEvents(await harness.drain(signals)).isEmpty)

        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallView(placement: .limit))
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        #expect(labEvents(await harness.drain(signals)) == ["lab.exposed \(Self.headline) \(variant)", "lab.converted \(Self.headline) \(variant)"])
    }

    @Test func theVersionAndTheExposureSurviveARelaunch() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,a,b,c;paywall.view;paywall.purchase"])
        let first = harness.makeSignals()
        let variant = first.variant(of: Self.headline)
        await first.send(.paywallView(placement: .settings))
        _ = await harness.drain(first)

        let relaunched = harness.makeSignals()
        #expect(relaunched.variant(of: Self.headline) == variant)
        await relaunched.send(.paywallView(placement: .settings))
        await relaunched.send(.paywallPurchase(product: "com.example.pro"))
        #expect(labEvents(await harness.drain(relaunched)) == ["lab.converted \(Self.headline) \(variant ?? "-")"])
    }

    @Test func takingTheExperimentOutOfTheConfigEndsIt() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals()
        await signals.send(.paywallView(placement: .settings))
        _ = await harness.drain(signals)

        harness.config.value = MidgarConfig()
        #expect(signals.variant(of: Self.headline) == nil)
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        #expect(labEvents(await harness.drain(signals)).isEmpty)
    }

    @Test func aForcedVersionIsShownAndAnUnknownOneIsIgnored() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals()
        let picked = signals.variant(of: Self.headline)

        signals.forceVariant("outcome", of: Self.headline)
        #expect(signals.variant(of: Self.headline) == "outcome")
        signals.forceVariant("purple", of: Self.headline)
        #expect(signals.variant(of: Self.headline) == picked)
        signals.forceVariant(nil, of: Self.headline)
        #expect(signals.variant(of: Self.headline) == picked)
    }

    @Test func withUsageCountsOffThereIsNoVersionAndTheSeedIsForgotten() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals()
        _ = signals.variant(of: Self.headline)
        let file = MidgarSignalsStore(directory: harness.directory, appID: harness.appID).sibling("lab")
        #expect(FileManager.default.fileExists(atPath: file.path))

        signals.setEnabled(false)
        #expect(signals.variant(of: Self.headline) == nil)
        #expect(await eventually { !FileManager.default.fileExists(atPath: file.path) })

        harness.config.value = try killedSignalsConfig()
        signals.setEnabled(true)
        #expect(signals.variant(of: Self.headline) == nil)
    }

    @Test func aTestInstallSeesItsVersionButIsNeverCounted() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals(isTestInstall: { true })
        await signals.noteActive()
        await signals.flush()

        #expect(signals.variant(of: Self.headline) != nil)
        await signals.send(.paywallView(placement: .settings))
        await signals.flush()
        #expect(harness.sentBatches.isEmpty)
        #expect(signals.lab.wasExposed(Self.headline) == false)
    }

    @Test func theSeedNeverAppearsInWhatIsSent() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.config.value = try running([Self.headline: "control,outcome;paywall.view;paywall.purchase"])
        let signals = harness.makeSignals()
        await signals.send(.paywallView(placement: .settings))
        await signals.send(.paywallPurchase(product: "com.example.pro"))
        _ = await harness.drain(signals)

        let file = MidgarSignalsStore(directory: harness.directory, appID: harness.appID).sibling("lab")
        let state = try JSONDecoder().decode(MidgarLabState.self, from: Data(contentsOf: file))
        let bodies = harness.host.requests.compactMap(\.body).map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(!bodies.contains(String(state.seed)))
        #expect(!harness.host.requests.contains { $0.headers.values.contains { $0.contains(String(state.seed)) } })
    }
}
