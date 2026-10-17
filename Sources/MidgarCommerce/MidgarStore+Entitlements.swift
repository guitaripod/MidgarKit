import Foundation

extension MidgarStore {
    /// One grant per name, the longer-lived winning and the sources of both kept, ordered by name.
    static func collapse(_ grants: [MidgarEntitlement]) -> [MidgarEntitlement] {
        var byName: [String: MidgarEntitlement] = [:]
        for grant in grants {
            byName[grant.name] = byName[grant.name].map { $0.merged(with: grant) } ?? grant
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// The grants in the ledger snapshot that are valid at `date`, for this app's own entries and for the cross-app entitlement names the configuration lists; every other app's entries grant nothing here. A non-consumable stays as long as the snapshot, which is dropped on an identity or environment change. A subscription needs a snapshot at most seven days old, and an expiry (or grace expiry) after `date`.
    func ledgerEntitlements(at date: Date) -> [MidgarEntitlement] {
        guard let snapshot = state.ledger else {
            return []
        }
        let isFresh = date.timeIntervalSince(snapshot.fetchedAt) <= Self.subscriptionCacheLifetime
        return snapshot.entitlements.compactMap { entry in
            let name = Self.entitlementName(of: entry, configuration: configuration)
            guard entry.app == configuration.appID || configuration.crossAppEntitlements.contains(name) else {
                return nil
            }
            let ownership: MidgarEntitlement.Ownership = entry.ownership == "FAMILY_SHARED" ? .familyShared : .purchased
            switch entry.kind {
            case "non_consumable":
                return MidgarEntitlement(
                    name: name, productID: entry.productId, kind: .nonConsumable, expirationDate: nil,
                    isInGracePeriod: false, ownership: ownership, sources: .ledger, app: entry.app
                )
            case "subscription":
                guard isFresh, let expiry = Self.activeExpiry(of: entry, at: date) else {
                    return nil
                }
                return MidgarEntitlement(
                    name: name, productID: entry.productId, kind: .subscription, expirationDate: expiry.date,
                    isInGracePeriod: expiry.isGrace, ownership: ownership, sources: .ledger, app: entry.app
                )
            default:
                return nil
            }
        }
    }

    /// The registry's entitlement name, else this app's map for its own product, else the product id.
    private static func entitlementName(of entry: LedgerEntitlement, configuration: MidgarStoreConfiguration) -> String {
        entry.entitlement ?? (entry.app == configuration.appID ? configuration.entitlementsByProduct[entry.productId] : nil) ?? entry.productId
    }

    /// The end of the paid period when it is still ahead, else the end of the grace period when the ledger says the subscription is in grace and that is still ahead.
    private static func activeExpiry(of entry: LedgerEntitlement, at date: Date) -> (date: Date, isGrace: Bool)? {
        if let expires = entry.expiresDate.map({ Date(timeIntervalSince1970: $0 / 1000) }), expires > date {
            return (expires, false)
        }
        if entry.inGracePeriod, let grace = entry.graceExpiresDate.map({ Date(timeIntervalSince1970: $0 / 1000) }), grace > date {
            return (grace, true)
        }
        return nil
    }

    func publishIfChanged() {
        let current = entitlements
        if current != lastPublished {
            lastPublished = current
            emit(.entitlementsChanged)
        }
    }
}
