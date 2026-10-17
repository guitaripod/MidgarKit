import Foundation
import MidgarCore
import StoreKit

/// A verified purchase as another service needs to see it: the transaction id, the product and the signed transaction (the JWS StoreKit produced).
public struct MidgarPurchaseReceipt: Sendable, Equatable, Codable {
    public let productID: String
    public let transactionID: String
    public let signedTransaction: String
    /// `production`, `sandbox` or `xcode`. A transaction signed by Xcode's local certificate (StoreKit testing) cannot be verified by any server.
    public let environment: String

    public init(productID: String, transactionID: String, signedTransaction: String, environment: String) {
        self.productID = productID
        self.transactionID = transactionID
        self.signedTransaction = signedTransaction
        self.environment = environment
    }

    init(_ transaction: StoreTransaction) {
        self.init(
            productID: transaction.productID,
            transactionID: String(transaction.id),
            signedTransaction: transaction.jws,
            environment: transaction.environment.rawValue
        )
    }
}

/// What ``MidgarStore/purchaseReceipt(_:)`` ended in: ``MidgarPurchaseResult`` with the receipt of a completed purchase.
public enum MidgarReceiptResult: Sendable, Equatable {
    /// The transaction was verified, finished, queued for the ledger and entitlements were updated.
    case purchased(MidgarPurchaseReceipt)
    case pending
    case cancelled
}

extension MidgarStore {
    /// Buys a configured product exactly like ``purchase(_:)`` and returns the verified transaction. Used for consumables whose grant lives in another service, such as credit packs.
    public func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult {
        try await purchaseReceipt(productID, confirmation: nil)
    }

    #if os(iOS) || os(visionOS)
    /// ``purchaseReceipt(_:)`` confirming in `scene`. This is the call on visionOS.
    @available(iOS 17.0, visionOS 1.0, *)
    @MainActor
    public func purchaseReceipt(_ productID: String, confirmIn scene: UIScene) async throws -> MidgarReceiptResult {
        try await purchaseReceipt(productID, confirmation: StoreConfirmation(anchor: scene))
    }
    #endif

    #if os(macOS)
    /// ``purchaseReceipt(_:)`` confirming in `window`.
    @MainActor
    public func purchaseReceipt(_ productID: String, confirmIn window: NSWindow) async throws -> MidgarReceiptResult {
        try await purchaseReceipt(productID, confirmation: StoreConfirmation(anchor: window))
    }
    #endif
}
