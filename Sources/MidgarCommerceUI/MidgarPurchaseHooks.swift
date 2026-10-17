import MidgarCommerce
import StoreKit
import SwiftUI

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension View {
    /// Makes the purchases of every StoreKit view below this one (`SubscriptionStoreView`, `StoreView`, `ProductView`) belong to `store`.
    ///
    /// The view still runs the purchase sheet, anchors it to its own scene or window (which is what visionOS needs) and handles upgrades and offers. This modifier adds the two things the money path needs: the Midgar ID as `appAccountToken` through `.inAppPurchaseOptions`, and the result handed to ``MidgarStore/complete(_:)`` through `.onInAppPurchaseCompletion`, so verification, the report queue, finish, the signal and the entitlements are the same as for ``MidgarStore/purchase(_:)``. A completion action also replaces StoreKit's default failure alert, so a failed purchase arrives as ``MidgarPaywallEvent/failed(message:)``.
    ///
    /// Why not `.onInAppPurchaseStart`: it reports only that a purchase began, with the product and no result, so it cannot hand the transaction to the store. Why not `\.purchase`: that environment action is for custom buttons, not for the purchase buttons inside `SubscriptionStoreView`.
    public func midgarPurchases(
        store: MidgarStore,
        onEvent: @escaping @MainActor (MidgarPaywallEvent) -> Void
    ) -> some View {
        inAppPurchaseOptions { _ in
            await store.purchaseOptions()
        }
        .onInAppPurchaseCompletion { product, result in
            let outcome = await Self.complete(result, in: store)
            onEvent(MidgarPaywallEvent.event(for: outcome, productID: product.id))
        }
    }

    private static func complete(
        _ result: Result<Product.PurchaseResult, any Error>,
        in store: MidgarStore
    ) async -> Result<MidgarPurchaseResult, any Error> {
        switch result {
        case .success(let purchase):
            do {
                return .success(try await store.complete(purchase))
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}
