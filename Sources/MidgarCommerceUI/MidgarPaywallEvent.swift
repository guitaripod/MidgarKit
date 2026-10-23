import Foundation
import MidgarCommerce

/// Where a paywall's purchase or restore ended. The app listens to close the paywall, unlock a feature or tell its review policy about trouble.
public enum MidgarPaywallEvent: Sendable, Equatable {
    /// A purchase was verified and handed to the store. The entitlements have changed.
    case purchased(productID: String)
    /// The purchase needs approval (Ask to Buy). The approved transaction arrives later through ``MidgarStore/events()``.
    case pending
    /// The customer closed the purchase sheet.
    case cancelled
    /// A restore found purchases.
    case restored
    /// A restore finished and the customer has no purchases.
    case nothingToRestore
    /// A purchase failed. The message is what the paywall showed. Report it to the review policy with `notePurchaseFailure()`.
    case failed(message: String)
    /// A restore failed. The message is what the paywall showed. Restoring is not buying, so it is not a purchase failure.
    case restoreFailed(message: String)
    /// The customer closed the offer code sheet and a purchase arrived through it. The transaction itself arrives through ``MidgarStore/events()`` like any other that the app did not start.
    case redeemed

    /// True for the events after which the paywall has done its job: a purchase, a restore or a redemption that gave the customer something.
    public var isSuccess: Bool {
        switch self {
        case .purchased, .restored, .redeemed:
            return true
        case .pending, .cancelled, .nothingToRestore, .failed, .restoreFailed:
            return false
        }
    }

    /// The event for what the store answered after a StoreKit view ran a purchase.
    static func event(for result: Result<MidgarPurchaseResult, any Error>, productID: String) -> MidgarPaywallEvent {
        switch result {
        case .success(.purchased):
            return .purchased(productID: productID)
        case .success(.pending):
            return .pending
        case .success(.cancelled):
            return .cancelled
        case .failure(let error):
            return .failed(message: message(for: error))
        }
    }

    /// What to tell the customer about a purchase error.
    static func message(for error: any Error) -> String {
        if case MidgarStoreError.unverifiedTransaction = error {
            return MidgarCommerceUIStrings.purchaseUnverified
        }
        return MidgarCommerceUIStrings.purchaseFailed
    }
}

/// The links a paywall must carry. The app passes its own, because the terms and the privacy policy are the app's.
public struct MidgarPaywallLinks: Sendable, Equatable {
    public let termsOfUse: URL
    public let privacyPolicy: URL

    public init(termsOfUse: URL, privacyPolicy: URL) {
        self.termsOfUse = termsOfUse
        self.privacyPolicy = privacyPolicy
    }
}
