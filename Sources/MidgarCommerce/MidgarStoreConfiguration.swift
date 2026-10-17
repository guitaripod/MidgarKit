import Foundation
import MidgarCore

/// What the store needs to know about the app. Product ids and entitlement names come from the app (later generated from the registry's `[commerce]` table); the code holds no prices and no product decisions.
public struct MidgarStoreConfiguration: Sendable {
    /// How much of the purchase path this app hands to MidgarCommerce.
    public enum Mode: Sendable, Equatable {
        /// MidgarCommerce owns purchase, restore and finish, and listens to `Transaction.updates`. Registry engines `storekit2` and `rc-observer` (RevenueCat only observes).
        case purchases
        /// MidgarCommerce only reads the ledger's entitlements and touches no transaction. Registry engine `rc-full`, until the app's migration.
        case readOnly
    }

    /// The registry slug. Names the persisted file and is the `X-App-ID` of the HTTP client.
    public let appID: String
    /// Every product this app sells and MidgarCommerce may handle. A transaction for any other product is left alone, unfinished and unreported, because another system (AICredits, RevenueCat) owns it.
    public let productIDs: [String]
    /// Product id to entitlement name. Products without an entry are bought and reported but grant nothing on this device.
    public let entitlementsByProduct: [String: String]
    public let mode: Mode
    /// Where the queue and the ledger cache live. Defaults to `<Application Support>/Midgar`.
    public let directory: URL?

    public init(
        appID: String,
        productIDs: [String],
        entitlementsByProduct: [String: String],
        mode: Mode = .purchases,
        directory: URL? = nil
    ) {
        self.appID = appID
        self.productIDs = productIDs
        self.entitlementsByProduct = entitlementsByProduct
        self.mode = mode
        self.directory = directory
    }
}

/// The one thing the store asks of the identity: the Midgar ID for `appAccountToken`. ``MidgarIdentity`` is the production conformance.
public protocol MidgarStoreIdentity: Sendable {
    var midgarId: String { get async throws }
}

extension MidgarIdentity: MidgarStoreIdentity {}
