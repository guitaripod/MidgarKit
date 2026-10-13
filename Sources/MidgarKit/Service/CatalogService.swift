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

    /// The catalog shipped inside the package, as apps, for a first paint with no network and no
    /// cache. Icons come from the bundled fallbacks.
    nonisolated static func bundledApps() -> [MidgarApp] {
        bundledCatalog().filter { !$0.isStaged }.map { merge(entry: $0, live: nil) }.sorted(by: ordering)
    }

    /// Builds the storefront fresh: pulls the curated catalog, enriches with live App Store data for
    /// the user's region, applies exclusions, sorts, and persists the snapshot **only when
    /// enrichment succeeded** so an offline refresh can never clobber the rich cached snapshot.
    /// `enriched` reports whether live App Store data was merged in.
    func build(config: MidgarConfig, ignoringOwnBundle: Bool = false) async -> (apps: [MidgarApp], enriched: Bool) {
        let exclusions = ignoringOwnBundle ? Set(config.excludedBundleIDs.map { $0.lowercased() }) : Set(config.resolvedExclusions)
        let catalog = await resolveCatalog(config: config)
        let entries = catalog.apps.filter { !exclusions.contains($0.bundleId.lowercased()) }
        guard !entries.isEmpty else { return ([], false) }

        let live = await itunes.lookup(ids: entries.map(\.appId), storefront: config.resolvedStorefront)
        let enriched = !live.isEmpty
        let expectedArtistID = catalog.developer?.artistId

        var seen = Set<String>()
        let apps = entries
            .filter { Self.isVisible($0, live: live, enriched: enriched, expectedArtistID: expectedArtistID) }
            .map { Self.merge(entry: $0, live: live[$0.appId]) }
            .sorted(by: Self.ordering)
            .filter { seen.insert($0.appId).inserted }

        if enriched, !apps.isEmpty { cache.saveSnapshot(apps) }
        return (apps, enriched)
    }

    /// Decides whether an entry is shown. Staged entries wait for the App Store to return them. An
    /// entry the store omits while it answers for the others is not sold in this region, so it is
    /// hidden. With no live data at all everything stays, so the portal still works offline.
    static func isVisible(
        _ entry: CatalogEntry,
        live: [String: ITunesApp],
        enriched: Bool,
        expectedArtistID: String?
    ) -> Bool {
        if entry.isStaged && live[entry.appId] == nil { return false }
        if enriched && live[entry.appId] == nil { return false }
        return belongsToDeveloper(entry, live: live[entry.appId], expectedArtistID: expectedArtistID)
    }

    /// Same as ``build(config:)`` but keeps the host app's own entry, which the portal shows as
    /// the "you are here" marker instead of hiding.
    func buildIncludingHost(config: MidgarConfig) async -> [MidgarApp] {
        var withoutExclusions = config
        withoutExclusions.excludedBundleIDs = []
        let own = Bundle.main.bundleIdentifier?.lowercased()
        let extra = Set(config.excludedBundleIDs.map { $0.lowercased() })
        let result = await build(config: withoutExclusions, ignoringOwnBundle: true)
        return result.apps.filter { app in
            let id = app.bundleId.lowercased()
            return id == own || !extra.contains(id)
        }
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

    static func merge(entry: CatalogEntry, live: ITunesApp?) -> MidgarApp {
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
            screenshotURLs: screenshots(entry: entry, live: live),
            rating: live?.averageUserRating,
            ratingCount: live?.userRatingCount,
            formattedPrice: live?.formattedPrice,
            platforms: entry.platforms ?? [.ios],
            topics: entry.topics ?? [],
            related: entry.related ?? [],
            family: entry.family,
            value: entry.value ?? 0.5
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
