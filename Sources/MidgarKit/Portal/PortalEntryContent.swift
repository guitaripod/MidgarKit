import Foundation

/// What the entry card shows: the same ranking the portal uses, read from cache or the bundled
/// catalog so the card never waits on the network, with a once-a-day background refresh that keeps
/// the cache current.
@MainActor
enum PortalEntryContent {
    static let refreshKey = "com.midgar.entry.lastRefresh"
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    static func ranked(hostBundleID: String?, installed: Set<String>) -> [MidgarApp] {
        let cached = CatalogService().cachedSnapshot()
        let apps = cached.isEmpty ? CatalogService.bundledApps() : cached
        return PortalRanking.order(apps: apps, hostBundleID: hostBundleID, installed: installed)
    }

    static func refreshIfStale(config: MidgarConfig, now: Date = Date(), defaults: UserDefaults = .standard) {
        let last = defaults.object(forKey: refreshKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) > refreshInterval else { return }
        defaults.set(now, forKey: refreshKey)
        Task.detached(priority: .background) {
            _ = await CatalogService().buildIncludingHost(config: config)
        }
    }

    static func subtitle(appCount: Int) -> String {
        MidgarStrings.entrySubtitle(appCount: appCount)
    }
}
