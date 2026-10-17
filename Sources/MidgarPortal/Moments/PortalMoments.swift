import Foundation

/// The rules of contextual cross-sell. An app names a moment (`Midgar.moment("export")`), the registry says which related app to offer there, and these rules say whether to offer it now. Everything here is a pure decision so the frequency cap, the ownership check and the registry mapping are testable without a screen.
enum PortalMoments {
    /// How long a moment stays quiet after it offered an app.
    static let interval: TimeInterval = 14 * 24 * 60 * 60

    /// The placement every moment reports and credits installs to.
    static let placement = "feature"

    /// Why a moment offers nothing.
    enum Skip: Equatable, Sendable {
        case unknownHost
        case unknownMoment
        case notAvailableHere
        case alreadyOwned
        case alreadyInstalled
        case shownRecently
    }

    enum Decision: Equatable, Sendable {
        case present(MidgarApp)
        case skip(Skip)
    }

    /// - Parameters:
    ///   - host: The catalog entry of the app calling the moment.
    ///   - catalog: Every app the portal knows, one record per store listing.
    ///   - ownedSlugs: The slugs of the apps the Midgar ID has a session in, or `nil` when that is unknown (no Midgar ID, offline). Unknown ownership never blocks an offer; an install detected on this device still does.
    ///   - installed: Lowercased bundle ids detected on this device.
    ///   - lastShown: When this moment last offered an app.
    static func decide(
        moment: String,
        host: MidgarApp?,
        catalog: [MidgarApp],
        ownedSlugs: Set<String>?,
        installed: Set<String>,
        lastShown: Date?,
        now: Date,
        platform: MidgarPlatform
    ) -> Decision {
        guard let host else { return .skip(.unknownHost) }
        guard let slug = host.moments[moment], slug != host.slug else { return .skip(.unknownMoment) }
        guard let target = catalog.first(where: { $0.slug == slug && $0.platforms.contains(platform) }) else {
            return .skip(.notAvailableHere)
        }
        if ownedSlugs?.contains(slug) == true { return .skip(.alreadyOwned) }
        if installed.contains(target.bundleId.lowercased()) { return .skip(.alreadyInstalled) }
        if let lastShown, now.timeIntervalSince(lastShown) < interval { return .skip(.shownRecently) }
        return .present(target)
    }
}

/// When each moment last offered an app, kept in the host app's own defaults so the cap persists per app across launches.
struct MomentHistory {
    static let keyPrefix = "com.midgar.moment.lastShown."

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastShown(_ moment: String) -> Date? {
        defaults.object(forKey: Self.keyPrefix + moment) as? Date
    }

    func markShown(_ moment: String, at date: Date) {
        defaults.set(date, forKey: Self.keyPrefix + moment)
    }
}
