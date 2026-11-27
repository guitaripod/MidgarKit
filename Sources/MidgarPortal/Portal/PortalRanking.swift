import Foundation

/// Decides which apps sit closest to the core. The aim is downloads: apps the user already has
/// move outward, apps related to the one they are using move inward, and the host app itself goes
/// to the rim as the "you are here" marker.
enum PortalRanking {
    static let relatedBonus = 2.0
    static let topicBonus = 0.8
    static let familyBonus = 0.6
    static let affinityWeight = 1.6
    static let featuredBonus = 0.3
    static let installedPenalty = 1.5
    static let orderTieBreak = 0.002

    static func order(
        apps catalog: [MidgarApp],
        hostBundleID: String?,
        installed: Set<String>,
        platform: MidgarPlatform = .current
    ) -> [MidgarApp] {
        let apps = onePerProduct(catalog, hostBundleID: hostBundleID, platform: platform)
        let host = apps.first { $0.bundleId.caseInsensitiveCompare(hostBundleID ?? "") == .orderedSame }
        let others = apps.filter { $0.appId != host?.appId }
        let ranked = others.sorted { lhs, rhs in
            let left = score(lhs, host: host, installed: installed)
            let right = score(rhs, host: host, installed: installed)
            if left != right { return left > right }
            return lhs.order < rhs.order
        }
        return ranked + (host.map { [$0] } ?? [])
    }

    /// A product sold as several store records (Flaccy for iPhone and Flaccy for Mac share the slug
    /// `flaccy` and the same icon) gets one cell, or the portal shows the same icon twice. The record
    /// kept is the host's, else one made for this platform, else one that runs here, else the first
    /// in the catalog. Apps without a slug are always kept.
    static func onePerProduct(_ apps: [MidgarApp], hostBundleID: String?, platform: MidgarPlatform) -> [MidgarApp] {
        let host = hostBundleID?.lowercased()
        var kept: [String: (app: MidgarApp, fit: Int)] = [:]
        for app in apps {
            guard let slug = app.slug else { continue }
            let fit = platformFit(of: app, host: host, platform: platform)
            if let current = kept[slug], current.fit >= fit { continue }
            kept[slug] = (app, fit)
        }
        return apps.filter { app in
            guard let slug = app.slug else { return true }
            return kept[slug]?.app.appId == app.appId
        }
    }

    /// How well a store record suits this device, higher is better.
    private static func platformFit(of app: MidgarApp, host: String?, platform: MidgarPlatform) -> Int {
        if app.bundleId.lowercased() == host { return 3 }
        if app.platforms.first == platform { return 2 }
        return app.platforms.contains(platform) ? 1 : 0
    }

    static func score(_ app: MidgarApp, host: MidgarApp?, installed: Set<String>) -> Double {
        var total = affinityWeight * affinity(of: app, to: host)
        total += app.value
        if app.featured { total += featuredBonus }
        if installed.contains(app.bundleId.lowercased()) { total -= installedPenalty }
        total -= Double(app.order) * orderTieBreak
        return total
    }

    static func affinity(of app: MidgarApp, to host: MidgarApp?) -> Double {
        guard let host else { return 0 }
        var total = 0.0
        let linked = host.related.contains { $0.caseInsensitiveCompare(app.bundleId) == .orderedSame }
            || app.related.contains { $0.caseInsensitiveCompare(host.bundleId) == .orderedSame }
        if linked { total += relatedBonus }
        total += topicBonus * Double(Set(host.topics).intersection(app.topics).count)
        if let family = host.family, family == app.family { total += familyBonus }
        return total
    }
}
