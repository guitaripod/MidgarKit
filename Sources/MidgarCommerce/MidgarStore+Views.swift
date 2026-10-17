import Foundation
import StoreKit

extension MidgarStore {
    /// The purchase options a StoreKit view must use so its purchases carry the Midgar ID as `appAccountToken`. Pass them from `.inAppPurchaseOptions`. Empty when the identity cannot answer right now: a payment never waits on our backend, and the ledger binds the transaction to the ID later.
    public func purchaseOptions() async -> Set<Product.PurchaseOption> {
        guard let token = await accountToken() else {
            return []
        }
        return [.appAccountToken(token)]
    }

    /// Takes the result of a purchase a StoreKit view ran (`SubscriptionStoreView`, `StoreView`, `ProductView`) through the same money path as ``purchase(_:)``: verification, the on-disk report queue, finish, the signal, the events and the entitlements. Call it from `.onInAppPurchaseCompletion`. A product that is not one of the store's configured products throws ``MidgarStoreError/unknownProduct(_:)``.
    public func complete(_ result: Product.PurchaseResult) async throws -> MidgarPurchaseResult {
        switch result {
        case .success(let verification):
            return try await complete(StorePurchaseOutcome.success(LiveStoreKit.map(verification)))
        case .pending:
            return try await complete(StorePurchaseOutcome.pending)
        case .userCancelled:
            return try await complete(StorePurchaseOutcome.userCancelled)
        @unknown default:
            throw MidgarStoreError.storeKit("StoreKit returned a purchase result this version does not know.")
        }
    }

    func complete(_ outcome: StorePurchaseOutcome) async throws -> MidgarPurchaseResult {
        try requirePurchases()
        switch outcome {
        case .pending:
            log("commerce: purchase is pending approval")
            return .pending
        case .userCancelled:
            return .cancelled
        case .success(let verification):
            let productID = Self.productID(of: verification)
            guard handledProducts.contains(productID) else {
                throw MidgarStoreError.unknownProduct(productID)
            }
            try await handle(verification, origin: .purchase)
            return .purchased
        }
    }

    private static func productID(of verification: StoreVerification) -> String {
        switch verification {
        case .verified(let transaction), .unverified(let transaction, _):
            return transaction.productID
        }
    }
}
