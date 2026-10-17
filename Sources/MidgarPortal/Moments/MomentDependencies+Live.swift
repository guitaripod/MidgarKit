import Foundation
import MidgarCore

#if (os(iOS) || os(visionOS)) && !targetEnvironment(macCatalyst)
extension MomentDependencies {
    /// The real catalog (cached or bundled, never the network), install detection, Midgar ID ownership and overlay.
    static func live(config: MidgarConfig) -> MomentDependencies {
        MomentDependencies(
            hostBundleID: Bundle.main.bundleIdentifier,
            catalog: {
                let cached = CatalogService().cachedSnapshot()
                return cached.isEmpty ? CatalogService.bundledApps() : cached
            },
            installed: { InstalledApps.detect(in: $0) },
            ownedSlugs: { await liveOwnedSlugs(config: config) },
            history: MomentHistory(),
            presenter: SKOverlayPresenter()
        )
    }

    private static func liveOwnedSlugs(config: MidgarConfig) async -> Set<String>? {
        guard let client = config.account else { return nil }
        let snapshot = await PortalAccountDirectory.account(for: client).snapshot()
        return snapshot.appSlugs.map(Set.init)
    }
}
#endif
