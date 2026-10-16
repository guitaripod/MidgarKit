import XCTest
@testable import MidgarPortal

final class MidgarTests: XCTestCase {

    func testBundledCatalogLoadsEveryApp() {
        let entries = CatalogService.bundledCatalog()
        XCTAssertEqual(entries.count, 16, "Bundled fallback should ship all 16 apps")
        XCTAssertTrue(entries.allSatisfy { !$0.appId.isEmpty && !$0.bundleId.isEmpty })
        XCTAssertTrue(entries.allSatisfy { !($0.platforms ?? []).isEmpty })
        XCTAssertTrue(entries.allSatisfy { midgarRGBA(hex: $0.accent) != nil })
    }

    func testBundledRelatedAppsExistInTheCatalog() {
        let entries = CatalogService.bundledCatalog()
        let bundles = Set(entries.map(\.bundleId))
        for entry in entries {
            for related in entry.related ?? [] {
                XCTAssertTrue(bundles.contains(related), "\(entry.bundleId) lists unknown related app \(related)")
            }
        }
    }

    func testEveryBundledAppHasAFallbackIcon() async {
        for entry in CatalogService.bundledCatalog() {
            let icon = await midgarBundledIcon(entry.appId, maxPixel: 60, scale: 2)
            XCTAssertNotNil(icon, "Missing bundled icon for \(entry.bundleId)")
        }
    }

    func testBundledAppsAreAllVisibleAndMergeEveryField() {
        let apps = CatalogService.bundledApps()
        XCTAssertEqual(apps.count, 16)
        let flaccyMac = apps.first { $0.bundleId == "com.midgarcorp.flaccy.mac" }
        XCTAssertEqual(flaccyMac?.platforms, [.mac])
        XCTAssertEqual(flaccyMac?.family, "flaccy")
    }

    func testBundledCatalogIdentifiersAreUnique() {
        let entries = CatalogService.bundledCatalog()
        XCTAssertEqual(Set(entries.map(\.appId)).count, entries.count)
        XCTAssertEqual(Set(entries.map(\.bundleId)).count, entries.count)
    }

    func testBundledCatalogHasFeaturedApps() {
        let entries = CatalogService.bundledCatalog()
        XCTAssertTrue(entries.contains { $0.featured == true })
    }

    func testBundledIconIsDownsampledToTheRequestedSize() async {
        let icon = await midgarBundledIcon("6779927672", maxPixel: 60, scale: 2)
        let longestEdge = max(icon?.size.width ?? 0, icon?.size.height ?? 0)
        XCTAssertGreaterThan(longestEdge, 0)
        XCTAssertLessThanOrEqual(longestEdge, 60, "Icon should be downsampled to the target size")
    }

    func testOrderingPutsFeaturedFirstThenByOrder() {
        let a = makeApp(id: "1", featured: false, order: 0)
        let b = makeApp(id: "2", featured: true, order: 5)
        let c = makeApp(id: "3", featured: false, order: 1)
        let sorted = [a, b, c].sorted(by: CatalogService.ordering)
        XCTAssertEqual(sorted.map(\.appId), ["2", "1", "3"])
    }

    func testPriceLabelCollapsesFreeToGet() {
        XCTAssertEqual(makeApp(price: nil).priceLabel, "GET")
        XCTAssertEqual(makeApp(price: "Free").priceLabel, "GET")
        XCTAssertEqual(makeApp(price: "free").priceLabel, "GET")
        XCTAssertEqual(makeApp(price: "$9.99").priceLabel, "$9.99")
    }

    func testHasRatingRequiresCountAndValue() {
        XCTAssertFalse(makeApp(rating: 4.5, ratingCount: 0).hasRating)
        XCTAssertFalse(makeApp(rating: 0, ratingCount: 10).hasRating)
        XCTAssertTrue(makeApp(rating: 4.5, ratingCount: 10).hasRating)
    }

    func testHexParsing() throws {
        XCTAssertNil(midgarRGBA(hex: nil))
        XCTAssertNil(midgarRGBA(hex: "#12"))
        XCTAssertNil(midgarRGBA(hex: "#GggGgg"))
        let white = try XCTUnwrap(midgarRGBA(hex: "#FFFFFF"))
        XCTAssertEqual(white.r, 1, accuracy: 0.001)
        XCTAssertEqual(white.a, 1, accuracy: 0.001)
        let half = midgarRGBA(hex: "00000080")
        XCTAssertEqual(half?.a ?? 0, 0.5, accuracy: 0.01)
    }

    func testConfigExcludesOwnBundleIdentifier() {
        let config = MidgarConfig()
        let own = Bundle.main.bundleIdentifier?.lowercased()
        XCTAssertNotNil(own)
        XCTAssertTrue(config.resolvedExclusions.contains(own!))
    }

    func testConfigEndpointPaths() {
        let config = MidgarConfig()
        XCTAssertEqual(config.catalogURL.absoluteString.hasSuffix("/v1/catalog"), true)
        XCTAssertEqual(config.eventURL.absoluteString.hasSuffix("/v1/event"), true)
    }

    func testStoreURLFormat() {
        XCTAssertEqual(makeApp(id: "123").storeURL.absoluteString, "https://apps.apple.com/app/id123")
    }

    func testBundledCatalogDeclaresDeveloperArtist() {
        XCTAssertEqual(CatalogService.loadBundledResponse()?.developer?.artistId, "1484270247")
    }

    func testDeveloperGuardKeepsEntriesWithoutAnExpectationOrLiveData() {
        XCTAssertTrue(CatalogService.belongsToDeveloper(makeEntry(), live: nil, expectedArtistID: nil))
        XCTAssertTrue(CatalogService.belongsToDeveloper(makeEntry(), live: nil, expectedArtistID: "1484270247"))
        XCTAssertTrue(CatalogService.belongsToDeveloper(makeEntry(), live: makeITunes(artistId: nil), expectedArtistID: "1484270247"))
    }

    func testDeveloperGuardKeepsMatchAndDropsMismatch() {
        XCTAssertTrue(CatalogService.belongsToDeveloper(makeEntry(), live: makeITunes(artistId: 1484270247), expectedArtistID: "1484270247"))
        XCTAssertFalse(CatalogService.belongsToDeveloper(makeEntry(), live: makeITunes(artistId: 999), expectedArtistID: "1484270247"))
    }

    func testScreenshotsPreferLiveThenCatalogThenIpad() {
        let phone = [URL(string: "https://x/p1")!]
        let ipad = [URL(string: "https://x/ipad1")!]
        let curated = [URL(string: "https://x/c1")!]
        let entry = makeEntry(screenshots: curated)

        XCTAssertEqual(CatalogService.screenshots(entry: entry, live: makeITunes(artistId: nil, phone: phone, ipad: ipad)), phone)
        XCTAssertEqual(CatalogService.screenshots(entry: entry, live: makeITunes(artistId: nil, phone: [], ipad: ipad)), curated)
        XCTAssertEqual(CatalogService.screenshots(entry: makeEntry(), live: makeITunes(artistId: nil, phone: [], ipad: ipad)), ipad)
        XCTAssertEqual(CatalogService.screenshots(entry: makeEntry(), live: nil), [])
    }

    func testLegacyAppJSONDecodesWithDefaults() throws {
        let json = #"{"appId":"1","bundleId":"com.example.one","name":"One"}"#
        let app = try JSONDecoder().decode(MidgarApp.self, from: Data(json.utf8))
        XCTAssertEqual(app.platforms, [.ios])
        XCTAssertEqual(app.topics, [])
        XCTAssertEqual(app.value, 0.5)
        XCTAssertFalse(app.featured)
    }

    func testStagedEntriesAppearOnlyOnceTheStoreReturnsThem() {
        let staged = makeEntry(appId: "9", status: "staged")
        XCTAssertFalse(CatalogService.isVisible(staged, live: [:], enriched: false, expectedArtistID: nil))
        XCTAssertFalse(CatalogService.isVisible(staged, live: ["1": makeITunes(artistId: nil)], enriched: true, expectedArtistID: nil))
        XCTAssertTrue(CatalogService.isVisible(staged, live: ["9": makeITunes(artistId: nil)], enriched: true, expectedArtistID: nil))
    }

    func testEntriesTheStoreOmitsAreHiddenOnlyWhenTheStoreAnswered() {
        let entry = makeEntry(appId: "5")
        XCTAssertTrue(CatalogService.isVisible(entry, live: [:], enriched: false, expectedArtistID: nil))
        XCTAssertFalse(CatalogService.isVisible(entry, live: ["1": makeITunes(artistId: nil)], enriched: true, expectedArtistID: nil))
        XCTAssertTrue(CatalogService.isVisible(entry, live: ["5": makeITunes(artistId: nil)], enriched: true, expectedArtistID: nil))
    }

    func testCampaignTokenIsSanitisedAndShort() {
        let config = MidgarConfig(placement: "Settings Row!")
        XCTAssertLessThanOrEqual(config.campaignToken.count, 40)
        XCTAssertFalse(config.campaignToken.contains(" "))
        XCTAssertTrue(config.campaignToken.hasSuffix("-settingsrow"))
    }

    func testTelemetryPropsCarryStorefrontPlacementAndPromotedApp() {
        let telemetry = Telemetry(config: MidgarConfig(storefront: "FI", placement: "portal"))
        XCTAssertEqual(
            telemetry.props(.tap, appId: "123"),
            ["appId": "123", "storefront": "fi", "placement": "portal"]
        )
        XCTAssertEqual(MidgarEvent.portalOpen.rawValue, "portal_open")
    }

    func testShortNameDropsTheMarketingSuffix() {
        XCTAssertEqual(makeApp(name: "Psywave: AI Playlist Maker").shortName, "Psywave")
        XCTAssertEqual(makeApp(name: "Embr \u{2014} Live Streams").shortName, "Embr")
        XCTAssertEqual(makeApp(name: "Solar Beam").shortName, "Solar Beam")
    }

    func testACatalogAssignedSchemeWinsOverTheBundleIdentifier() throws {
        let json = #"{"appId":"9","bundleId":"com.example.New","name":"New","scheme":"midgar-07"}"#
        let app = try JSONDecoder().decode(MidgarApp.self, from: Data(json.utf8))
        XCTAssertEqual(app.urlScheme, "midgar-07")
        XCTAssertEqual(InstalledApps.launchURL(for: app)?.absoluteString, "midgar-07://")
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
        XCTAssertEqual(CatalogService.merge(entry: entry, live: nil).urlScheme, "midgar-07")
    }

    func testURLSchemeIsTheLowercasedBundleIdentifier() {
        XCTAssertEqual(makeApp(id: "7").urlScheme, "com.example.7")
        let mixed = MidgarApp(appId: "1", bundleId: "com.guitaripod.Pixie", name: "P")
        XCTAssertEqual(mixed.urlScheme, "com.guitaripod.pixie")
        XCTAssertEqual(InstalledApps.launchURL(for: mixed)?.absoluteString, "com.guitaripod.pixie://")
    }

    func testASlotIsDecodedBesideTheLegacySchemeAndUrlSchemeKeepsItsMeaning() throws {
        let json = #"{"appId":"9","bundleId":"com.example.Old","name":"Old","slot":"midgar-05"}"#
        let app = try JSONDecoder().decode(MidgarApp.self, from: Data(json.utf8))
        XCTAssertEqual(app.slot, "midgar-05")
        XCTAssertNil(app.scheme)
        XCTAssertEqual(app.urlScheme, "com.example.old")
        XCTAssertEqual(app.reachableSchemes, ["midgar-05", "com.example.old"])
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
        XCTAssertEqual(CatalogService.merge(entry: entry, live: nil).slot, "midgar-05")
    }

    func testSlotAndLegacySchemesAreBothChecked() {
        let app = MidgarApp(appId: "9", bundleId: "com.example.Old", name: "Old", slot: "midgar-05")
        XCTAssertEqual(InstalledApps.installedURL(for: app) { $0.scheme == "midgar-05" }?.absoluteString, "midgar-05://")
        XCTAssertEqual(InstalledApps.installedURL(for: app) { $0.scheme == "com.example.old" }?.absoluteString, "com.example.old://")
    }

    func testDetectionPrefersTheSlotWhenBothAnswer() {
        let app = MidgarApp(appId: "9", bundleId: "com.example.Both", name: "Both", slot: "midgar-05")
        var asked: [String] = []
        let url = InstalledApps.installedURL(for: app) { candidate in
            asked.append(candidate.absoluteString)
            return true
        }
        XCTAssertEqual(url?.absoluteString, "midgar-05://")
        XCTAssertEqual(asked, ["midgar-05://"])
    }

    func testANewAppWithOnlyASchemeIsReachedBySchemeThenBundleIdentifier() {
        let app = MidgarApp(appId: "9", bundleId: "com.example.New", name: "New", scheme: "midgar-07")
        XCTAssertEqual(app.reachableSchemes, ["midgar-07", "com.example.new"])
        XCTAssertEqual(InstalledApps.installedURL(for: app) { $0.scheme == "midgar-07" }?.absoluteString, "midgar-07://")
    }

    func testAnAppWithoutASlotOrSchemeIsReachedByItsBundleIdentifierOnly() {
        let app = MidgarApp(appId: "9", bundleId: "com.example.Plain", name: "Plain")
        XCTAssertEqual(app.reachableSchemes, ["com.example.plain"])
        var asked = 0
        let url = InstalledApps.installedURL(for: app) { _ in asked += 1; return true }
        XCTAssertEqual(url?.absoluteString, "com.example.plain://")
        XCTAssertEqual(asked, 1)
    }

    func testDetectionFindsNothingWhenNoSchemeAnswers() {
        let app = MidgarApp(appId: "9", bundleId: "com.example.None", name: "None", scheme: "midgar-07", slot: "midgar-05")
        var asked: [String] = []
        let url = InstalledApps.installedURL(for: app) { candidate in
            asked.append(candidate.absoluteString)
            return false
        }
        XCTAssertNil(url)
        XCTAssertEqual(asked, ["midgar-05://", "midgar-07://", "com.example.none://"])
    }

    func testReachableSchemesDropDuplicates() {
        let app = MidgarApp(appId: "9", bundleId: "Midgar-05", name: "Odd", scheme: "midgar-05", slot: "MIDGAR-05")
        XCTAssertEqual(app.reachableSchemes, ["midgar-05"])
    }

    private func makeEntry(appId: String = "1", screenshots: [URL]? = nil, status: String? = nil) -> CatalogEntry {
        var object: [String: Any] = ["appId": appId, "bundleId": "com.example.\(appId)", "name": "X"]
        if let screenshots { object["screenshots"] = screenshots.map(\.absoluteString) }
        if let status { object["status"] = status }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(CatalogEntry.self, from: data)
    }

    private func makeITunes(artistId: Int?, phone: [URL]? = nil, ipad: [URL]? = nil) -> ITunesApp {
        ITunesApp(trackId: 1, artistId: artistId, bundleId: nil, trackName: nil, primaryGenreName: nil, formattedPrice: nil, averageUserRating: nil, userRatingCount: nil, artworkUrl512: nil, artworkUrl100: nil, screenshotUrls: phone, ipadScreenshotUrls: ipad)
    }

    private func makeApp(
        id: String = "1",
        featured: Bool = false,
        order: Int = 0,
        price: String? = nil,
        rating: Double? = nil,
        ratingCount: Int? = nil,
        name: String? = nil
    ) -> MidgarApp {
        MidgarApp(
            appId: id,
            bundleId: "com.example.\(id)",
            name: name ?? "Example \(id)",
            tagline: "Tagline",
            genre: "Utilities",
            accentHex: "#7C5CFF",
            featured: featured,
            order: order,
            iconURL: nil,
            screenshotURLs: [],
            rating: rating,
            ratingCount: ratingCount,
            formattedPrice: price
        )
    }
}
