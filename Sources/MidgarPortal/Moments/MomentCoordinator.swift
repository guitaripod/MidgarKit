import Foundation
import os

/// Puts an App Store overlay on screen for an app.
@MainActor
protocol MomentPresenting {
    /// Returns `false` when nothing could be shown, such as no active window scene.
    func present(_ app: MidgarApp, campaignToken: String, providerToken: String?) -> Bool
}

/// What a call to ``Midgar/moment(_:config:)`` came to.
enum MomentOutcome: Equatable, Sendable {
    case presented(MidgarApp)
    case skipped(PortalMoments.Skip)
    case notPresented
    case gated
    case alreadyRunning
}

/// The moments being decided right now, so two calls for one moment cannot both pass the cap before either has recorded its offer.
@MainActor
final class MomentsInFlight {
    static let shared = MomentsInFlight()

    private var names = Set<String>()

    /// `false` when the moment is already running.
    func begin(_ moment: String) -> Bool { names.insert(moment).inserted }

    func end(_ moment: String) { names.remove(moment) }
}

/// Everything a moment reads or touches outside the rules, so a test can stand in for the screen, the disk and the network.
@MainActor
struct MomentDependencies {
    var hostBundleID: String?
    var catalog: () -> [MidgarApp]
    var installed: ([MidgarApp]) -> Set<String>
    var ownedSlugs: () async -> Set<String>?
    var history: MomentHistory
    var presenter: any MomentPresenting
    var inFlight: MomentsInFlight = .shared
    var now: () -> Date = { Date() }
    var platform: MidgarPlatform = .current
}

/// Runs one moment: decide from what is local, ask the identity service only when an offer is about to be made, present the overlay, remember it and report it.
@MainActor
enum MomentCoordinator {
    private static let log = Logger(subsystem: "com.midgar.storefront", category: "Moments")

    static func run(
        moment: String,
        config: MidgarConfig,
        dependencies: MomentDependencies,
        telemetry: Telemetry
    ) async -> MomentOutcome {
        guard config.gate == nil else { return .gated }
        guard dependencies.inFlight.begin(moment) else { return .alreadyRunning }
        defer { dependencies.inFlight.end(moment) }

        let catalog = dependencies.catalog().filter { app in
            !config.excludedBundleIDs.contains { $0.caseInsensitiveCompare(app.bundleId) == .orderedSame }
        }
        let host = catalog.first { $0.bundleId.caseInsensitiveCompare(dependencies.hostBundleID ?? "") == .orderedSame }
        let first = decide(moment, host: host, catalog: catalog, owned: nil, dependencies: dependencies)
        guard case .present = first else { return skipped(first, moment: moment) }

        let owned = await dependencies.ownedSlugs()
        let decision = decide(moment, host: host, catalog: catalog, owned: owned, dependencies: dependencies)
        guard case .present(let app) = decision else { return skipped(decision, moment: moment) }

        let shown = dependencies.presenter.present(
            app,
            campaignToken: config.campaignToken,
            providerToken: config.providerToken
        )
        guard shown else { return .notPresented }
        dependencies.history.markShown(moment, at: dependencies.now())
        await telemetry.record(.overlay, appId: app.appId)
        return .presented(app)
    }

    private static func decide(
        _ moment: String,
        host: MidgarApp?,
        catalog: [MidgarApp],
        owned: Set<String>?,
        dependencies: MomentDependencies
    ) -> PortalMoments.Decision {
        let candidates = host.flatMap { host in host.moments[moment] }.map { slug in catalog.filter { $0.slug == slug } } ?? []
        return PortalMoments.decide(
            moment: moment,
            host: host,
            catalog: catalog,
            ownedSlugs: owned,
            installed: dependencies.installed(candidates),
            lastShown: dependencies.history.lastShown(moment),
            now: dependencies.now(),
            platform: dependencies.platform
        )
    }

    private static func skipped(_ decision: PortalMoments.Decision, moment: String) -> MomentOutcome {
        guard case .skip(let reason) = decision else { return .notPresented }
        if reason == .unknownMoment {
            log.notice("moment \(moment, privacy: .public) is not in the registry's [portal.moments] for this app")
        }
        return .skipped(reason)
    }
}
