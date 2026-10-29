import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsCatalogTests {
    private typealias Entry = MidgarSignalCatalog.Entry

    private static let everyApp = Entry(name: "everyone", purpose: "Sent by every app.", uniqueness: .each)
    private static let alphaOnly = Entry(name: "alpha.only", purpose: "Sent by alpha.", uniqueness: .daily, apps: ["alpha"])
    private static let betaOnly = Entry(name: "beta.only", purpose: "Sent by beta.", uniqueness: .weekly, apps: ["beta"])
    private static let alphaAndGamma = Entry(name: "alpha.gamma", purpose: "Sent by alpha and gamma.", uniqueness: .monthly, apps: ["alpha", "gamma"])
    private static let notYet = Entry(name: "not.yet", purpose: "Sent by no code yet.", uniqueness: .lifetime, isReserved: true)
    private static let fixture = [everyApp, alphaOnly, betaOnly, alphaAndGamma, notYet]

    @Test func anAppGetsTheEventsWithNoLimitAndTheOnesLimitedToIt() {
        #expect(Self.fixture.allowed(for: "alpha").map(\.name) == ["everyone", "alpha.only", "alpha.gamma"])
        #expect(Self.fixture.allowed(for: "beta").map(\.name) == ["everyone", "beta.only"])
        #expect(Self.fixture.allowed(for: "gamma").map(\.name) == ["everyone", "alpha.gamma"])
    }

    @Test func anAppTheRegistryDoesNotLimitAnythingToGetsOnlyTheUnlimitedEvents() {
        #expect(Self.fixture.allowed(for: "delta").map(\.name) == ["everyone"])
        #expect(Self.fixture.allowed(for: nil).map(\.name) == ["everyone"])
        #expect(Self.fixture.allowed(for: "").map(\.name) == ["everyone"])
    }

    @Test func aSlugMatchesWholeAndExactly() {
        #expect(Self.fixture.allowed(for: "alph").map(\.name) == ["everyone"])
        #expect(Self.fixture.allowed(for: "Alpha").map(\.name) == ["everyone"])
        #expect(Self.fixture.allowed(for: "alpha-2").map(\.name) == ["everyone"])
    }

    @Test func reservedEventsAreLeftOutUnlessAsked() {
        #expect(!Self.fixture.allowed(for: "alpha").contains { $0.name == "not.yet" })
        #expect(Self.fixture.allowed(for: "alpha", includingReserved: true).map(\.name) == ["everyone", "alpha.only", "alpha.gamma", "not.yet"])
    }

    @Test func filteringKeepsTheCatalogsOrder() {
        let reversed = Array(Self.fixture.reversed())

        #expect(reversed.allowed(for: "alpha").map(\.name) == ["alpha.gamma", "alpha.only", "everyone"])
    }

    @Test func anEntryKnowsWhetherAnAppMaySendIt() {
        #expect(Self.everyApp.isAllowed(for: nil))
        #expect(Self.everyApp.isAllowed(for: "alpha"))
        #expect(Self.alphaOnly.isAllowed(for: "alpha"))
        #expect(!Self.alphaOnly.isAllowed(for: "beta"))
        #expect(!Self.alphaOnly.isAllowed(for: nil))
    }

    @Test func theGeneratedCatalogListsEveryEventInRegistryOrder() {
        #expect(MidgarSignalCatalog.entries.map(\.name) == MidgarSignal.allNames)
        #expect(Set(MidgarSignalCatalog.entries.map(\.name)).count == MidgarSignalCatalog.entries.count)
        #expect(MidgarSignalCatalog.entries.allSatisfy { !$0.purpose.isEmpty })
    }

    @Test func theGeneratedCatalogForAnAppDropsTheReservedEvents() {
        let sent = MidgarSignalCatalog.entries(for: "any-app")

        #expect(sent.allSatisfy { !$0.isReserved })
        #expect(sent.count == MidgarSignalCatalog.entries.filter { !$0.isReserved && $0.apps.isEmpty }.count)
        #expect(MidgarSignalCatalog.entries(for: "any-app", includingReserved: true).count == MidgarSignalCatalog.entries.filter { $0.apps.isEmpty }.count)
    }

    @Test func anEntryIsFoundByItsName() {
        #expect(MidgarSignalCatalog.entry(named: "paywall.view")?.uniqueness == .each)
        #expect(MidgarSignalCatalog.entry(named: "nothing.like.this") == nil)
    }

    @Test func eachEntryAgreesWithTheTypedEventOfTheSameName() throws {
        for signal in Self.everyEvent {
            let entry = try #require(MidgarSignalCatalog.entry(named: signal.name), "\(signal.name) is not in the catalog")
            #expect(entry.uniqueness == signal.uniqueness, "\(signal.name) uniqueness")
            #expect(entry.carriesCohort == signal.carriesCohort, "\(signal.name) cohort")
            let declared = Set(entry.props.map(\.name) + entry.measurements.map(\.name))
            #expect(declared == Set(signal.props.keys), "\(signal.name) props")
        }
        #expect(Self.everyEvent.count == MidgarSignalCatalog.entries.count, "add the new event to everyEvent")
    }

    @Test func aPropListsExactlyTheValuesTheTypedEventAccepts() throws {
        let view = try #require(MidgarSignalCatalog.entry(named: "paywall.view"))
        let step = try #require(MidgarSignalCatalog.entry(named: "funnel.step"))
        let tap = try #require(MidgarSignalCatalog.entry(named: "tap"))

        #expect(view.props == [.init(name: "placement", values: .list(MidgarSignal.Placement.allCases.map(\.rawValue)))])
        #expect(step.props.first?.values == .list(MidgarSignal.FunnelStep.allCases.map(\.rawValue)))
        #expect(tap.props.map(\.name) == ["appId", "storefront", "placement"])
        #expect(tap.props[0].values == .apps)
        #expect(tap.props[1].values == .list(MidgarSignal.Storefront.allCases.map(\.rawValue)))
        #expect(tap.props[1].isOptional)
        #expect(!tap.props[2].isOptional)
    }

    @Test func productsAndMeasurementsKeepTheirRules() throws {
        let purchase = try #require(MidgarSignalCatalog.entry(named: "paywall.purchase"))
        let metrics = try #require(MidgarSignalCatalog.entry(named: "metrics.daily"))
        let diagnostics = try #require(MidgarSignalCatalog.entry(named: "metrics.diagnostics"))

        #expect(purchase.props == [.init(name: "product", values: .products)])
        #expect(metrics.props.isEmpty)
        #expect(metrics.measurements.first == .init(name: "coldLaunchMs", minimum: 0, maximum: 600_000))
        #expect(diagnostics.measurements.first == .init(name: "crashes", minimum: 0, maximum: 100_000, isInteger: true))
    }

    @Test func theInstallWeekIsOnlyOnTheEventsTheRegistryMarks() {
        let withWeek = MidgarSignalCatalog.entries.filter(\.carriesCohort).map(\.name)

        #expect(withWeek == ["app.active", "funnel.step"])
    }

    @Test func theGeneratedUniquenessCoversTheWordsAnAppCanSay() {
        #expect(MidgarSignalCatalog.entries.contains { $0.uniqueness == .perPeriod })
        #expect(MidgarSignalCatalog.entries.contains { $0.uniqueness == .lifetime })
        #expect(MidgarSignalCatalog.entries.contains { $0.uniqueness == .each })
    }

    @Test func aSignalsClientKnowsTheSlugItWasConfiguredWith() {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }

        #expect(harness.makeSignals().appID == "dream-eater")
    }

    private static let everyEvent: [MidgarSignal] = [
        .appLaunch, .appActive(period: .day), .onboardingComplete, .paywallView(placement: .settings),
        .paywallPurchase(product: "com.example.pro"), .paywallCheckout(outcome: .started, product: "com.example.pro"),
        .funnelStep(step: .samplePlayed), .portalOpen(storefront: .fi, placement: .entry),
        .impression(appId: "psywave", storefront: .fi, placement: .entry), .tap(appId: "psywave", storefront: .fi, placement: .entry),
        .loaded(appId: "psywave", storefront: .fi, placement: .entry), .launch(appId: "psywave", storefront: .fi, placement: .entry),
        .overlay(appId: "psywave", storefront: .fi, placement: .entry),
        .metricsDaily(coldLaunchMs: 1, hangSecondsPerHour: 1, foregroundSeconds: 1, peakMemoryMB: 1),
        .metricsDiagnostics(crashes: 1, hangs: 1, diskWrites: 1, cpuExceptions: 1),
    ]
}
