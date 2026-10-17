import Foundation

/// One thing the person owns in a Midgar app, as "Your Midgar" lists it.
struct OwnedItem: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case lifetime
        case subscription(until: Date, inGrace: Bool)
    }

    let name: String
    let kind: Kind

    /// The line under the name: "Lifetime", or when the subscription's paid period (or its billing grace period) ends.
    var detail: String {
        switch kind {
        case .lifetime:
            return MidgarStrings.lifetime
        case .subscription(let until, let inGrace):
            let date = until.formatted(date: .abbreviated, time: .omitted)
            return inGrace ? MidgarStrings.billingIssue(until: date) : MidgarStrings.activeUntil(date)
        }
    }

    /// When the grant stops counting: never for a lifetime purchase.
    fileprivate var lastsUntil: Date {
        switch kind {
        case .lifetime: return .distantFuture
        case .subscription(let until, _): return until
        }
    }
}

/// A Midgar app the person has, with what they own in it.
struct YourApp: Identifiable, Hashable, Sendable {
    let app: MidgarApp
    let owned: [OwnedItem]

    var id: String { app.appId }
}

/// Everything the "Your Midgar" panel shows: the apps the person has and a few more worth a look.
struct YourMidgarSection: Equatable, Sendable {
    let yours: [YourApp]
    let suggestions: [MidgarApp]
}

/// Builds the section from the catalog and what the identity service and the ledger said. Display only: nothing here grants an entitlement in any app.
enum YourMidgarBuilder {
    static let suggestionLimit = 3

    /// - Parameters:
    ///   - snapshot: The account answers. Unknown (no Midgar ID, offline, refused) builds nothing, so the portal looks as it did before.
    ///   - catalog: The apps for this device in ranking order, host included. Entries without a registry slug cannot be matched to the account, so a catalog with none builds nothing.
    ///   - installed: Lowercased bundle ids detected on this device. They are never suggested.
    static func build(
        snapshot: PortalAccountSnapshot,
        catalog: [MidgarApp],
        hostBundleID: String?,
        installed: Set<String> = [],
        platform: MidgarPlatform = .current,
        now: Date = Date()
    ) -> YourMidgarSection? {
        guard !snapshot.isUnknown, catalog.contains(where: { $0.slug != nil }) else { return nil }
        let owned = ownedItems(snapshot.entitlements ?? [], now: now)
        let slugs = Set(snapshot.appSlugs ?? []).union(owned.keys)
        let apps = oneRecordPerProduct(catalog, platform: platform)
        let host = hostBundleID?.lowercased()

        let yours = apps
            .filter { app in app.slug.map(slugs.contains) ?? false }
            .map { YourApp(app: $0, owned: owned[$0.slug ?? ""] ?? []) }
            .sorted { order($0, before: $1, host: host) }
        guard !yours.isEmpty else { return nil }

        let suggestions = apps
            .filter { app in
                guard let slug = app.slug else { return false }
                return !slugs.contains(slug)
                    && app.bundleId.lowercased() != host
                    && !installed.contains(app.bundleId.lowercased())
                    && app.platforms.contains(platform)
            }
            .prefix(suggestionLimit)
        return YourMidgarSection(yours: yours, suggestions: Array(suggestions))
    }

    /// The host first, then apps with purchases, then the rest, each group by name.
    private static func order(_ lhs: YourApp, before rhs: YourApp, host: String?) -> Bool {
        let leftHost = lhs.app.bundleId.lowercased() == host
        let rightHost = rhs.app.bundleId.lowercased() == host
        if leftHost != rightHost { return leftHost }
        if lhs.owned.isEmpty != rhs.owned.isEmpty { return !lhs.owned.isEmpty }
        return lhs.app.shortName.localizedCaseInsensitiveCompare(rhs.app.shortName) == .orderedAscending
    }

    /// A product with several store records (Flaccy on iPhone and Mac) counts once, as the record that runs on this device, else the first. Apps keep the catalog's order.
    static func oneRecordPerProduct(_ catalog: [MidgarApp], platform: MidgarPlatform) -> [MidgarApp] {
        var chosen: [String: MidgarApp] = [:]
        for app in catalog {
            guard let slug = app.slug else { continue }
            if let kept = chosen[slug], kept.platforms.contains(platform) || !app.platforms.contains(platform) { continue }
            chosen[slug] = app
        }
        var seen = Set<String>()
        return catalog.compactMap { app in
            guard let slug = app.slug, chosen[slug]?.appId == app.appId, seen.insert(slug).inserted else { return nil }
            return app
        }
    }

    /// The active grants per app slug. Within one app a name appears once, as the grant that lasts longest, and lifetime purchases come before subscriptions.
    static func ownedItems(_ entitlements: [PortalEntitlement], now: Date) -> [String: [OwnedItem]] {
        var best: [String: [String: OwnedItem]] = [:]
        for entitlement in entitlements {
            guard let item = item(for: entitlement, now: now) else { continue }
            if let kept = best[entitlement.app]?[item.name], kept.lastsUntil >= item.lastsUntil { continue }
            best[entitlement.app, default: [:]][item.name] = item
        }
        return best.mapValues { items in
            items.values.sorted { lhs, rhs in
                if lhs.lastsUntil != rhs.lastsUntil { return lhs.lastsUntil > rhs.lastsUntil }
                return lhs.name < rhs.name
            }
        }
    }

    private static func item(for entitlement: PortalEntitlement, now: Date) -> OwnedItem? {
        let name = displayName(entitlement.entitlement)
        switch entitlement.kind {
        case "non_consumable":
            return OwnedItem(name: name, kind: .lifetime)
        case "subscription":
            let end = entitlement.inGracePeriod ? entitlement.graceExpiresDate : entitlement.expiresDate
            guard let end else { return nil }
            let date = Date(timeIntervalSince1970: end / 1000)
            guard date > now else { return nil }
            return OwnedItem(name: name, kind: .subscription(until: date, inGrace: entitlement.inGracePeriod))
        default:
            return nil
        }
    }

    /// `pro` is shown as "Pro". A grant with no entitlement name shows as "Unlocked".
    static func displayName(_ entitlement: String?) -> String {
        guard let trimmed = entitlement?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else {
            return MidgarStrings.unlocked
        }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }
}
