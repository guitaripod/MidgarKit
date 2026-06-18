import XCTest
@testable import MidgarKit

final class MidgarTests: XCTestCase {

    func testBundledCatalogLoadsEveryApp() {
        let entries = CatalogService.bundledCatalog()
        XCTAssertEqual(entries.count, 11, "Bundled fallback should ship all 11 apps")
        XCTAssertTrue(entries.allSatisfy { !$0.appId.isEmpty && !$0.bundleId.isEmpty })
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

    func testInReviewAppsHaveBundledIcons() {
        for appId in ["6777952645", "6779927672"] {
            XCTAssertNotNil(midgarBundledIcon(appId), "Missing bundled icon for \(appId)")
        }
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

    private func makeEntry(appId: String = "1", screenshots: [URL]? = nil) -> CatalogEntry {
        CatalogEntry(appId: appId, bundleId: "com.example.\(appId)", name: "X", tagline: nil, genre: nil, accent: nil, featured: nil, order: nil, icon: nil, screenshots: screenshots)
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
        ratingCount: Int? = nil
    ) -> MidgarApp {
        MidgarApp(
            appId: id,
            bundleId: "com.example.\(id)",
            name: "Example \(id)",
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
