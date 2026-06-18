import Foundation

/// Orchestrates the storefront data pipeline:
/// remote catalog → device-region App Store enrichment → curated/bundled fallback,
/// caching the result for instant, offline-capable launches.
actor CatalogService {
    private let session: URLSession
    private let itunes: ITunesClient
    private let cache = DiskCache()

    init(session: URLSession = .midgar) {
        self.session = session
        self.itunes = ITunesClient(session: session)
    }

    /// Last fully-enriched result persisted on disk, for instant first paint. May be empty.
    nonisolated func cachedSnapshot() -> [MidgarApp] {
        DiskCache().loadSnapshot()
    }

    /// Builds the storefront fresh: pulls the curated catalog, enriches with live App Store data for
    /// the user's region, applies exclusions, sorts, and persists the snapshot **only when
    /// enrichment succeeded** so an offline refresh can never clobber the rich cached snapshot.
    /// `enriched` reports whether live App Store data was merged in.
    func build(config: MidgarConfig) async -> (apps: [MidgarApp], enriched: Bool) {
        let exclusions = Set(config.resolvedExclusions)
        let catalog = await resolveCatalog(config: config)
        let entries = catalog.apps.filter { !exclusions.contains($0.bundleId.lowercased()) }
        guard !entries.isEmpty else { return ([], false) }

        let live = await itunes.lookup(ids: entries.map(\.appId), storefront: config.resolvedStorefront)
        let enriched = !live.isEmpty
        let expectedArtistID = catalog.developer?.artistId

        var seen = Set<String>()
        let apps = entries
            .filter { Self.belongsToDeveloper($0, live: live[$0.appId], expectedArtistID: expectedArtistID) }
            .map { merge(entry: $0, live: live[$0.appId]) }
            .sorted(by: Self.ordering)
            .filter { seen.insert($0.appId).inserted }

        if enriched, !apps.isEmpty { cache.saveSnapshot(apps) }
        return (apps, enriched)
    }

    private func resolveCatalog(config: MidgarConfig) async -> CatalogResponse {
        if let remote = await fetchRemoteCatalog(config: config) {
            cache.saveCatalog(remote)
            return remote
        }
        if let disk = cache.loadCatalog() { return disk }
        return Self.loadBundledResponse() ?? CatalogResponse(version: 0, updatedAt: nil, developer: nil, apps: [])
    }

    private func fetchRemoteCatalog(config: MidgarConfig) async -> CatalogResponse? {
        do {
            let (data, response) = try await session.data(from: config.catalogURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(CatalogResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func merge(entry: CatalogEntry, live: ITunesApp?) -> MidgarApp {
        MidgarApp(
            appId: entry.appId,
            bundleId: entry.bundleId,
            name: live?.trackName ?? entry.name,
            tagline: entry.tagline,
            genre: live?.primaryGenreName ?? entry.genre,
            accentHex: entry.accent,
            featured: entry.featured ?? false,
            order: entry.order ?? 999,
            iconURL: live?.artworkUrl512 ?? live?.artworkUrl100 ?? entry.icon,
            screenshotURLs: Self.screenshots(entry: entry, live: live),
            rating: live?.averageUserRating,
            ratingCount: live?.userRatingCount,
            formattedPrice: live?.formattedPrice
        )
    }

    /// Keeps an entry unless live App Store data proves it belongs to a *different* developer than
    /// the catalog's. Entries without live data are always kept (preserving offline degradation),
    /// so Midgar can only ever promote the catalog owner's own apps.
    static func belongsToDeveloper(_ entry: CatalogEntry, live: ITunesApp?, expectedArtistID: String?) -> Bool {
        guard let expectedArtistID, let artistID = live?.artistId else { return true }
        return String(artistID) == expectedArtistID
    }

    /// The legacy iTunes feed often omits screenshots, so prefer live iPhone shots, then the
    /// catalog's curated (ASC-sourced) shots, then live iPad shots.
    static func screenshots(entry: CatalogEntry, live: ITunesApp?) -> [URL] {
        if let phone = live?.screenshotUrls, !phone.isEmpty { return phone }
        if let curated = entry.screenshots, !curated.isEmpty { return curated }
        return live?.ipadScreenshotUrls ?? []
    }

    static func ordering(_ lhs: MidgarApp, _ rhs: MidgarApp) -> Bool {
        if lhs.featured != rhs.featured { return lhs.featured }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.name < rhs.name
    }

    static func loadBundledResponse() -> CatalogResponse? {
        guard let url = Bundle.module.url(forResource: "catalog.fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(CatalogResponse.self, from: data)
        else { return nil }
        return response
    }

    static func bundledCatalog() -> [CatalogEntry] {
        loadBundledResponse()?.apps ?? []
    }
}
