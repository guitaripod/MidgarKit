import Foundation

/// One thing the customer may use, named by the app's entitlement map (`pro`, `premium`) or, for a ledger entry from another app, by the registry's entitlement name.
public struct MidgarEntitlement: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case nonConsumable
        case subscription
    }

    public enum Ownership: String, Sendable, Hashable {
        case purchased
        case familyShared
    }

    /// Where the grant was seen. Both flags mean the ledger and this device agree.
    public struct Sources: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let ledger = Sources(rawValue: 1)
        public static let storeKit = Sources(rawValue: 2)
    }

    public let name: String
    public let productID: String
    public let kind: Kind
    /// Nil for a non-consumable. For a subscription the end of the paid period, or of the grace period when ``isInGracePeriod``.
    public let expirationDate: Date?
    public let isInGracePeriod: Bool
    public let ownership: Ownership
    public let sources: Sources
    /// The registry slug of the app that sold it, known only from the ledger.
    public let app: String?

    /// True while the grant is valid at `date`. A non-consumable never lapses; a subscription needs an expiration after `date`.
    func isActive(at date: Date) -> Bool {
        switch kind {
        case .nonConsumable:
            return true
        case .subscription:
            guard let expirationDate else {
                return false
            }
            return expirationDate > date
        }
    }

    /// The longer-lived of two grants of one name, with the sources of both. A grant without an expiration outlasts any other.
    func merged(with other: MidgarEntitlement) -> MidgarEntitlement {
        let winner = outlasts(other) ? self : other
        return MidgarEntitlement(
            name: winner.name,
            productID: winner.productID,
            kind: winner.kind,
            expirationDate: winner.expirationDate,
            isInGracePeriod: winner.isInGracePeriod,
            ownership: winner.ownership,
            sources: sources.union(other.sources),
            app: winner.app ?? other.app ?? app
        )
    }

    private func outlasts(_ other: MidgarEntitlement) -> Bool {
        switch (expirationDate, other.expirationDate) {
        case (nil, _):
            return true
        case (_, nil):
            return false
        case (let mine?, let theirs?):
            return mine >= theirs
        }
    }
}
