import Foundation

/// The App Store environment that signed a transaction. `xcode` covers StoreKit testing in Xcode and `SKTestSession`, whose transactions the ledger cannot verify.
enum StoreEnvironment: String, Sendable, Equatable {
    case production
    case sandbox
    case xcode
}

/// Whether the account owns the purchase or has it through Family Sharing.
enum StoreOwnership: Sendable, Equatable {
    case purchased
    case familyShared
}

/// The product types StoreKit sells.
enum StoreProductKind: Sendable, Equatable {
    case consumable
    case nonConsumable
    case nonRenewingSubscription
    case autoRenewableSubscription
}

/// What the store logic reads from one StoreKit transaction, with the action that finishes it. The live adapter fills it from `Transaction`, the unit tests from fakes.
struct StoreTransaction: Sendable {
    let id: UInt64
    let originalID: UInt64
    let productID: String
    let kind: StoreProductKind
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool
    let ownership: StoreOwnership
    let appAccountToken: UUID?
    let environment: StoreEnvironment
    let jws: String
    let finish: @Sendable () async -> Void
}

/// A transaction together with StoreKit's verdict on its signature.
enum StoreVerification: Sendable {
    case verified(StoreTransaction)
    case unverified(StoreTransaction, reason: String)
}

/// What a purchase call came back with.
enum StorePurchaseOutcome: Sendable {
    case success(StoreVerification)
    case pending
    case userCancelled
}

/// A product as the paywall shows it. Prices come from StoreKit, never from code.
public struct StoreProduct: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let displayPrice: String
}

/// The StoreKit calls `MidgarStore` makes, so its logic runs against fakes in unit tests and against `LiveStoreKit` in the app.
protocol MidgarStoreKit: Sendable {
    func products(for ids: [String]) async throws -> [StoreProduct]
    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome
    func updates() -> AsyncStream<StoreVerification>
    func currentEntitlements() async -> [StoreVerification]
    func sync() async throws
    func appEnvironment() async -> StoreEnvironment?
}
