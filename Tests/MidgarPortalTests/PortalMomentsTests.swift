import Foundation
import Testing
@testable import MidgarPortal

private let host = PortalFixtures.app("psywave", moments: ["export": "flaccy", "share": "embr"])
private let flaccyPhone = PortalFixtures.app("flaccy", bundle: "com.midgarcorp.flaccy", id: "1001")
private let flaccyMac = PortalFixtures.app("flaccy", bundle: "com.midgarcorp.flaccy.mac", id: "1002", platforms: [.mac])
private let embr = PortalFixtures.app("embr")
private let fixtureCatalog = [host, flaccyMac, flaccyPhone, embr]

private func decide(
    _ moment: String = "export",
    host: MidgarApp? = host,
    catalog: [MidgarApp] = fixtureCatalog,
    owned: Set<String>? = [],
    installed: Set<String> = [],
    lastShown: Date? = nil,
    platform: MidgarPlatform = .ios
) -> PortalMoments.Decision {
    PortalMoments.decide(
        moment: moment,
        host: host,
        catalog: catalog,
        ownedSlugs: owned,
        installed: installed,
        lastShown: lastShown,
        now: PortalFixtures.now,
        platform: platform
    )
}

@Suite struct PortalMomentRuleTests {
    @Test func aMomentOffersTheRelatedAppTheRegistryNamesForItOnThisPlatform() {
        #expect(decide() == .present(flaccyPhone))
        #expect(decide("share") == .present(embr))
        #expect(decide(platform: .mac) == .present(flaccyMac))
    }

    @Test func aMomentTheHostDoesNotNameOffersNothing() {
        #expect(decide("nowhere") == .skip(.unknownMoment))
        #expect(decide(host: nil) == .skip(.unknownHost))
    }

    @Test func aTargetThatHasNoRecordForThisPlatformOffersNothing() {
        #expect(decide("share", platform: .tvos) == .skip(.notAvailableHere))
        #expect(decide(catalog: [host, embr]) == .skip(.notAvailableHere))
    }

    @Test func anAppTheMidgarIDAlreadyHasIsNeverOffered() {
        #expect(decide(owned: ["flaccy"]) == .skip(.alreadyOwned))
        #expect(decide(owned: ["embr", "psywave"]) == .present(flaccyPhone))
    }

    @Test func unknownOwnershipDoesNotBlockAnOfferButAnInstallOnThisDeviceDoes() {
        #expect(decide(owned: nil) == .present(flaccyPhone))
        #expect(decide(owned: nil, installed: ["com.midgarcorp.flaccy"]) == .skip(.alreadyInstalled))
        #expect(decide(owned: nil, installed: ["com.midgarcorp.flaccy.mac"]) == .present(flaccyPhone))
    }

    @Test func aMomentStaysQuietForFourteenDaysAfterItOffered() {
        let day: TimeInterval = 86_400
        let now = PortalFixtures.now
        #expect(PortalMoments.interval == 14 * day)
        #expect(decide(lastShown: now.addingTimeInterval(-1)) == .skip(.shownRecently))
        #expect(decide(lastShown: now.addingTimeInterval(-13 * day)) == .skip(.shownRecently))
        #expect(decide(lastShown: now.addingTimeInterval(-14 * day + 1)) == .skip(.shownRecently))
        #expect(decide(lastShown: now.addingTimeInterval(-14 * day)) == .present(flaccyPhone))
        #expect(decide(lastShown: now.addingTimeInterval(-90 * day)) == .present(flaccyPhone))
        #expect(decide(lastShown: nil) == .present(flaccyPhone))
    }

    @Test func aMomentNeverOffersTheHostItself() {
        let selfish = PortalFixtures.app("psywave", moments: ["export": "psywave"])
        #expect(decide(host: selfish, catalog: [selfish]) == .skip(.unknownMoment))
    }

    @Test func theOrderOfTheChecksIsOwnershipThenInstallThenCap() {
        let recent = PortalFixtures.now.addingTimeInterval(-60)
        #expect(decide(owned: ["flaccy"], installed: ["com.midgarcorp.flaccy"], lastShown: recent) == .skip(.alreadyOwned))
        #expect(decide(installed: ["com.midgarcorp.flaccy"], lastShown: recent) == .skip(.alreadyInstalled))
    }
}

@Suite struct MomentHistoryTests {
    @Test func whenAMomentLastOfferedPersistsInTheAppsOwnDefaults() {
        let (defaults, cleanup) = PortalFixtures.defaults()
        defer { cleanup() }
        let history = MomentHistory(defaults: defaults)
        #expect(history.lastShown("export") == nil)

        history.markShown("export", at: PortalFixtures.now)
        #expect(MomentHistory(defaults: defaults).lastShown("export") == PortalFixtures.now)
        #expect(history.lastShown("share") == nil)
    }
}

@Suite struct MomentRegistryMappingTests {
    private func decodeEntry(_ json: String) throws -> CatalogEntry {
        try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
    }

    @Test func aCatalogEntryCarriesItsSlugAndMomentsIntoTheApp() throws {
        let entry = try decodeEntry(#"""
        {"appId": "1", "bundleId": "com.example.psywave", "name": "Psywave", "slug": "psywave",
         "related": ["com.midgarcorp.flaccy"], "moments": {"export": "flaccy", "share": "embr"}}
        """#)
        let app = CatalogService.merge(entry: entry, live: nil)
        #expect(app.slug == "psywave")
        #expect(app.moments == ["export": "flaccy", "share": "embr"])
    }

    @Test func anEntryWithoutThemHasNoMomentsAndNoSlug() throws {
        let app = CatalogService.merge(entry: try decodeEntry(#"{"appId": "1", "bundleId": "b", "name": "N"}"#), live: nil)
        #expect(app.slug == nil)
        #expect(app.moments.isEmpty)
    }

    @Test func aHostedEntryRegeneratedBeforeTheSlugExistedTakesItFromTheBundledCatalog() throws {
        let entry = try decodeEntry(#"{"appId": "6727000827", "bundleId": "com.marcusziade.psywave", "name": "Psywave"}"#)
        #expect(CatalogService.merge(entry: entry, live: nil).slug == "psywave")
        let own = try decodeEntry(#"{"appId": "6727000827", "bundleId": "com.marcusziade.psywave", "name": "Psywave", "slug": "psywave-x"}"#)
        #expect(CatalogService.merge(entry: own, live: nil).slug == "psywave-x")
    }

    @Test func theCachedSnapshotKeepsThemAndAnOlderSnapshotStillDecodes() throws {
        let kept = try JSONDecoder().decode(MidgarApp.self, from: JSONEncoder().encode(host))
        #expect(kept.slug == "psywave")
        #expect(kept.moments == host.moments)

        let old = #"{"appId": "1", "bundleId": "b", "name": "N"}"#
        let decoded = try JSONDecoder().decode(MidgarApp.self, from: Data(old.utf8))
        #expect(decoded.slug == nil)
        #expect(decoded.moments.isEmpty)
    }

    @Test func everyBundledAppCarriesItsRegistrySlugAndEveryMomentTargetIsInTheCatalog() {
        let apps = CatalogService.bundledApps()
        #expect(apps.allSatisfy { ($0.slug ?? "").isEmpty == false })
        let slugs = Set(apps.compactMap(\.slug))
        for app in apps {
            for (moment, target) in app.moments {
                #expect(slugs.contains(target), "\(app.bundleId) moment \(moment) names unknown slug \(target)")
                #expect(target != app.slug)
            }
        }
        let flaccy = apps.filter { $0.slug == "flaccy" }
        #expect(flaccy.count == 2)
    }
}

@MainActor
private final class OwnershipGate {
    private var continuation: CheckedContinuation<Set<String>?, Never>?
    private(set) var asked = 0

    func ask() async -> Set<String>? {
        asked += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func answer(_ owned: Set<String>?) {
        continuation?.resume(returning: owned)
        continuation = nil
    }
}

@MainActor
private struct Rig {
    let presenter = FakePresenter()
    let inFlight = MomentsInFlight()
    let clock = TestClock(PortalFixtures.now)
    let defaults: UserDefaults
    let cleanup: () -> Void
    var owned: () async -> Set<String>? = { [] }
    var installed: Set<String> = []
    var catalog: [MidgarApp] = fixtureCatalog
    var config = MidgarConfig(enableTelemetry: false, placement: PortalMoments.placement)

    init() {
        (defaults, cleanup) = PortalFixtures.defaults()
    }

    func run(_ moment: String = "export") async -> MomentOutcome {
        let dependencies = MomentDependencies(
            hostBundleID: "com.example.psywave",
            catalog: { catalog },
            installed: { [installed] apps in Set(apps.map { $0.bundleId.lowercased() }).intersection(installed) },
            ownedSlugs: owned,
            history: MomentHistory(defaults: defaults),
            presenter: presenter,
            inFlight: inFlight,
            now: { [clock] in clock.now },
            platform: .ios
        )
        return await MomentCoordinator.run(moment: moment, config: config, dependencies: dependencies, telemetry: Telemetry(config: config, signals: { nil }))
    }
}

@MainActor @Suite struct MomentCoordinatorTests {
    @Test func presentsTheOverlayWithTheHostFeatureCampaignTokenAndRemembersIt() async {
        let rig = Rig()
        defer { rig.cleanup() }
        let outcome = await rig.run()
        #expect(outcome == .presented(flaccyPhone))
        #expect(rig.presenter.shown == [.init(appId: "1001", campaignToken: rig.config.campaignToken, providerToken: MidgarConfig.defaultProviderToken)])
        #expect(rig.config.campaignToken.hasSuffix("-feature"))
        #expect(MomentHistory(defaults: rig.defaults).lastShown("export") == PortalFixtures.now)
    }

    @Test func offersAtMostOnceInFourteenDaysAndAgainAfterwards() async {
        let rig = Rig()
        defer { rig.cleanup() }
        _ = await rig.run()
        rig.clock.advance(13 * 86_400)
        #expect(await rig.run() == .skipped(.shownRecently))
        #expect(rig.presenter.shown.count == 1)

        rig.clock.advance(86_400)
        #expect(await rig.run() == .presented(flaccyPhone))
        #expect(rig.presenter.shown.count == 2)
    }

    @Test func eachMomentHasItsOwnCap() async {
        let rig = Rig()
        defer { rig.cleanup() }
        #expect(await rig.run("export") == .presented(flaccyPhone))
        #expect(await rig.run("share") == .presented(embr))
        #expect(await rig.run("export") == .skipped(.shownRecently))
    }

    @Test func staysQuietForAnAppThePersonHasAndKeepsTheCapFree() async {
        var rig = Rig()
        defer { rig.cleanup() }
        rig.owned = { ["flaccy", "psywave"] }
        #expect(await rig.run() == .skipped(.alreadyOwned))
        #expect(rig.presenter.shown.isEmpty)
        #expect(MomentHistory(defaults: rig.defaults).lastShown("export") == nil)
    }

    @Test func staysQuietForAnAppInstalledHereWhenOwnershipIsUnknown() async {
        var rig = Rig()
        defer { rig.cleanup() }
        rig.owned = { nil }
        rig.installed = ["com.midgarcorp.flaccy"]
        #expect(await rig.run() == .skipped(.alreadyInstalled))
    }

    @Test func unknownOwnershipStillOffers() async {
        var rig = Rig()
        defer { rig.cleanup() }
        rig.owned = { nil }
        #expect(await rig.run() == .presented(flaccyPhone))
    }

    @Test func asksTheIdentityServiceOnlyWhenAnOfferIsAboutToBeMade() async {
        var rig = Rig()
        defer { rig.cleanup() }
        let gate = OwnershipGate()
        rig.owned = { await gate.ask() }
        #expect(await rig.run("nowhere") == .skipped(.unknownMoment))

        let history = MomentHistory(defaults: rig.defaults)
        history.markShown("export", at: PortalFixtures.now)
        #expect(await rig.run("export") == .skipped(.shownRecently))
        #expect(gate.asked == 0)
    }

    @Test func aSecondCallForTheSameMomentWhileOneIsRunningDoesNothing() async {
        var rig = Rig()
        defer { rig.cleanup() }
        let gate = OwnershipGate()
        rig.owned = { await gate.ask() }
        let rig2 = rig
        let first = Task { await rig2.run() }
        for _ in 0..<1000 where gate.asked == 0 { await Task.yield() }
        #expect(gate.asked == 1)

        #expect(await rig.run() == .alreadyRunning)
        gate.answer([])
        #expect(await first.value == .presented(flaccyPhone))
        #expect(rig.presenter.shown.count == 1)
    }

    @Test func aHostWithAParentalGateNeverGetsAnOverlay() async {
        var rig = Rig()
        defer { rig.cleanup() }
        rig.config.gate = { true }
        #expect(await rig.run() == .gated)
        #expect(rig.presenter.shown.isEmpty)
    }

    @Test func anOverlayThatCouldNotBeShownIsNotCountedAgainstTheCap() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.presenter.succeeds = false
        #expect(await rig.run() == .notPresented)
        #expect(MomentHistory(defaults: rig.defaults).lastShown("export") == nil)

        rig.presenter.succeeds = true
        #expect(await rig.run() == .presented(flaccyPhone))
    }

    @Test func anAppTheHostExcludesIsNeverOffered() async {
        var rig = Rig()
        defer { rig.cleanup() }
        rig.config.excludedBundleIDs = ["COM.MIDGARCORP.FLACCY"]
        #expect(await rig.run() == .skipped(.notAvailableHere))
    }
}
