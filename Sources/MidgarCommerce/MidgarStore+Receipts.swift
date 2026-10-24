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
    /// Completes a purchase the customer started on the App Store product page (a promoted in-app purchase). StoreKit hands the running app the intent instead of charging, so without this the purchase never happens. It runs through the same money path as a purchase made in the app, with the Midgar ID as `appAccountToken`, and observers hear of it as ``MidgarStoreEvent/purchaseApproved(productID:)`` because no call of theirs started it (MidgarCredits reads the balance again and the ledger-fed grant credits a pack). A product this store does not sell is left alone; a cancel or a failure is logged.
    func purchaseFromAppStore(_ productID: String) async {
        guard handledProducts.contains(productID) else {
            log("commerce: ignored an App Store purchase of \(productID), which this store does not sell")
            return
        }
        do {
            switch try await purchaseReceipt(productID, confirmation: nil) {
            case .purchased:
                emit(.purchaseApproved(productID: productID))
            case .pending:
                break
            case .cancelled:
                log("commerce: the App Store purchase of \(productID) was cancelled")
            }
        } catch {
            log("commerce: the App Store purchase of \(productID) failed: \(error)")
        }
    }

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
