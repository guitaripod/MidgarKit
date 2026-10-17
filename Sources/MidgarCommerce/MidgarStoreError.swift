import Foundation

/// Why a ``MidgarStore`` call failed. Apps map these to their own copy.
public enum MidgarStoreError: Error, Sendable, Equatable {
    /// The product id is not one of the store's configured products, or StoreKit does not sell it.
    case unknownProduct(String)
    /// The store was configured read-only (an `rc-full` app): it never buys, restores or finishes anything.
    case readOnly
    /// StoreKit could not verify the transaction's signature. It was not granted, not finished and not reported.
    case unverifiedTransaction(productID: String)
    /// The platform cannot run this call from MidgarCommerce (a purchase on visionOS, an offer code sheet off iOS).
    case unsupportedPlatform
    /// StoreKit itself failed. Carries its description.
    case storeKit(String)
}

/// What a purchase ended in when it did not throw.
public enum MidgarPurchaseResult: Sendable, Equatable {
    /// The transaction was verified, finished, queued for the ledger and entitlements were updated.
    case purchased
    /// Ask to Buy or another approval is pending. The approved transaction arrives later through the updates listener.
    case pending
    case cancelled
}

/// What the store tells observers. Read ``MidgarStore/entitlements`` after `entitlementsChanged`.
public enum MidgarStoreEvent: Sendable, Equatable {
    case entitlementsChanged
    /// A new purchase arrived through the updates listener: an Ask to Buy approval, an offer code redemption or a purchase made on another device.
    case purchaseApproved(productID: String)
    /// A transaction failed verification and was refused.
    case refused(productID: String)
}
