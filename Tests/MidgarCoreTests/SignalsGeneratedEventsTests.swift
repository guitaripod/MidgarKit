import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsGeneratedEventsTests {
    @Test func aClosedSetEventCarriesItsNameAndRawValues() {
        let event = MidgarSignal.paywallView(placement: .settings)

        #expect(event.name == "paywall.view")
        #expect(event.props == ["placement": .string("settings")])
    }

    @Test func aTwoPropEventKeepsRegistryBackedValuesAsPlainStrings() {
        let event = MidgarSignal.paywallCheckout(outcome: .cancelled, product: "com.example.pro")

        #expect(event.name == "paywall.checkout")
        #expect(event.props == ["outcome": .string("cancelled"), "product": .string("com.example.pro")])
    }

    @Test func anOptionalPropIsLeftOutUntilItIsGiven() {
        let bare = MidgarSignal.impression(appId: "psywave", placement: .feature)
        let located = MidgarSignal.impression(appId: "psywave", storefront: .fi, placement: .feature)

        #expect(bare.props == ["appId": .string("psywave"), "placement": .string("feature")])
        #expect(located.props["storefront"] == .string("fi"))
        #expect(MidgarSignal.portalOpen(placement: .entry).props == ["placement": .string("entry")])
    }

    @Test func aStorefrontNamedLikeASwiftKeywordKeepsItsRawValue() {
        #expect(MidgarSignal.Storefront.in.rawValue == "in")
        #expect(MidgarSignal.Storefront.is.rawValue == "is")
        #expect(MidgarSignal.Storefront(rawValue: "no") == MidgarSignal.Storefront.no)
    }

    @Test func measurementsAreOptionalAndKeepTheirNumberKind() {
        let daily = MidgarSignal.metricsDaily(coldLaunchMs: 420.5, peakMemoryMB: 180)
        let diagnostics = MidgarSignal.metricsDiagnostics(crashes: 2, hangs: 0)

        #expect(daily.name == "metrics.daily")
        #expect(daily.props == ["coldLaunchMs": .double(420.5), "peakMemoryMB": .double(180)])
        #expect(diagnostics.props == ["crashes": .int(2), "hangs": .int(0)])
        #expect(MidgarSignal.metricsDaily().props.isEmpty)
    }

    @Test func eventsWithoutPropsSendNone() {
        #expect(MidgarSignal.appLaunch.name == "app.launch")
        #expect(MidgarSignal.appLaunch.props.isEmpty)
        #expect(MidgarSignal.onboardingComplete.name == "onboarding.complete")
    }

    @Test func uniquenessAndCohortAreCompiledIn() {
        #expect(MidgarSignal.appActive(period: .week).uniqueness == .perPeriod)
        #expect(MidgarSignal.funnelStep(step: .samplePlayed).uniqueness == .lifetime)
        #expect(MidgarSignal.paywallPurchase(product: "x").uniqueness == .each)
        #expect(MidgarSignal.appActive(period: .day).carriesCohort)
        #expect(MidgarSignal.funnelStep(step: .trialStarted).carriesCohort)
        #expect(!MidgarSignal.paywallView(placement: .limit).carriesCohort)
        #expect(MidgarSignal.Uniqueness.perPeriod.rawValue == "per-period")
    }

    @Test func theClosedSetsMatchWhatTheClientsSendToday() {
        #expect(MidgarSignal.Period.allCases.map(\.rawValue) == MidgarActivePeriod.allCases.map(\.rawValue))
        #expect(MidgarSignal.Placement.allCases.map(\.rawValue) == ["settings", "entry", "onboarding", "launch", "paywall", "feature", "limit"])
        #expect(MidgarSignal.FunnelStep.allCases.map(\.rawValue) == ["sample_played", "add_music_opened", "library_filled", "import_succeeded", "import_failed", "trial_started"])
        #expect(MidgarSignal.Outcome.allCases.map(\.rawValue) == ["started", "purchased", "pending", "cancelled", "failed"])
    }

    @Test func everyGeneratedEventBecomesAQueuedEventWithItsPropsIntact() throws {
        let events: [MidgarSignal] = [
            .appActive(period: .month), .paywallView(placement: .paywall), .funnelStep(step: .importFailed),
            .tap(appId: "6746733380", storefront: .us, placement: .launch), .metricsDiagnostics(crashes: 1),
        ]

        for event in events {
            let queued = try #require(MidgarSignalEvent(name: event.name, props: event.props))
            #expect(queued.name == event.name)
            #expect(queued.props == event.props)
        }
    }

    @Test func aGeneratedEventTravelsThroughTheSignalsClientAsItsNameAndProps() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()
        let event = MidgarSignal.paywallCheckout(outcome: .started, product: "com.example.pro")

        await signals.record(event.name, props: event.props)
        await signals.flush()

        let sent = try #require(harness.sentBatches.first?.first)
        #expect(sent["name"] as? String == "paywall.checkout")
        #expect(sent["props"] as? [String: String] == ["outcome": "started", "product": "com.example.pro"])
    }

    @Test func theListOfNamesIsTheCatalogsWhenTheMonorepoIsAround() throws {
        let catalog = try #require(Self.catalogNames())

        #expect(MidgarSignal.allNames == catalog)
        #expect(Set(MidgarSignal.allNames).count == MidgarSignal.allNames.count)
    }

    private static func catalogNames() -> [String]? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("registry/generated/signals-catalog.json")
        guard let data = try? Data(contentsOf: file),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = document["events"] as? [[String: Any]]
        else {
            return nil
        }
        return events.compactMap { $0["name"] as? String }
    }
}
