import Foundation
import MidgarCommerce
import MidgarCore

/// Why a ``MidgarCredits`` call failed. Cancellation is never wrapped: it surfaces as `CancellationError`. Apps map these cases to their own copy; each also has a user-facing description.
///
/// MidgarKit adds cases in minor releases; switch with `@unknown default`.
public enum MidgarCreditsError: Error, Sendable, Equatable, LocalizedError {
    /// Why credit packs cannot be sold.
    public enum Reason: Sendable, Equatable {
        /// The configuration lists no packs.
        case noPacks
        /// The pack id is not one of the configured packs.
        case unknownPack(String)
        /// The product is not a configured pack, or the store does not handle it: add ``MidgarCreditsConfiguration/productIDs`` to the store's product ids.
        case productNotSold(String)
        /// The store is read-only (an `rc-full` app until its migration), so it cannot buy.
        case purchasesDisabled
    }

    case offline
    /// The wallet answered 402. `balance` is the wallet balance right now, nil only when it could not be read.
    case insufficientCredits(balance: Int?)
    /// mako answered 503: the wallet cannot be reached. Nothing was charged; try again shortly.
    case walletUnavailable
    case notConfigured(Reason)
    /// The Midgar ID session was refused (401).
    case unauthorized
    /// The identity could not provide a token right now.
    case identityUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    /// mako will never credit this purchase. The customer was charged by the App Store; the message is mako's.
    case purchaseRejected(message: String)
    case store(MidgarStoreError)
    case server(status: Int, code: String?, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .offline:
            return NSLocalizedString(
                "You appear to be offline. Check your connection and try again.",
                bundle: .module,
                comment: "Shown when the credit balance or a credit purchase cannot reach Midgar because the device is offline"
            )
        case .insufficientCredits:
            return NSLocalizedString(
                "You do not have enough credits for this. Buy a credit pack to continue.",
                bundle: .module,
                comment: "Shown when an action needs more credits than the wallet holds"
            )
        case .walletUnavailable:
            return NSLocalizedString(
                "Your credit balance is temporarily unavailable. Nothing was charged. Try again in a moment.",
                bundle: .module,
                comment: "Shown when the credit wallet cannot be reached"
            )
        case .notConfigured:
            return NSLocalizedString(
                "Credit packs are not available in this app right now.",
                bundle: .module,
                comment: "Shown when the app has no credit pack to sell"
            )
        case .unauthorized:
            return NSLocalizedString(
                "Your session has expired. Sign in again.",
                bundle: .module,
                comment: "Shown when Midgar rejects the signed-in credentials while reading credits"
            )
        case .identityUnavailable:
            return NSLocalizedString(
                "Your Midgar ID is not ready yet. Try again in a moment.",
                bundle: .module,
                comment: "Shown when credits cannot be read because the Midgar ID has no access token yet"
            )
        case .rateLimited:
            return NSLocalizedString(
                "Too many requests. Try again in a moment.",
                bundle: .module,
                comment: "Shown when the credits service asks the app to slow down"
            )
        case .purchaseRejected:
            return NSLocalizedString(
                "The purchase could not be verified. If you were charged, contact support.",
                bundle: .module,
                comment: "Shown when the credits service refuses to credit a credit pack the customer paid for"
            )
        case .store, .server, .invalidResponse:
            return NSLocalizedString(
                "The credits request could not be completed. Try again later.",
                bundle: .module,
                comment: "Shown when a credit balance read or credit purchase failed for a reason the app cannot act on"
            )
        }
    }

    /// Maps a gateway failure. A 402 carries no balance here: the envelope's message holds it as text and ``MidgarHTTPError`` drops the message, so callers that want it read the balance afterwards.
    static func mapping(_ error: MidgarHTTPError) -> any Error {
        switch error {
        case .offline, .timeout:
            return MidgarCreditsError.offline
        case .unauthorized:
            return MidgarCreditsError.unauthorized
        case .paymentRequired:
            return MidgarCreditsError.insufficientCredits(balance: nil)
        case .rateLimited(let retryAfter, _):
            return MidgarCreditsError.rateLimited(retryAfter: retryAfter)
        case .notFound(let code):
            return MidgarCreditsError.server(status: 404, code: code, message: "Not found")
        case .server(let status, let code, let message):
            if status == 503 {
                return MidgarCreditsError.walletUnavailable
            }
            return MidgarCreditsError.server(status: status, code: code, message: message)
        case .decoding, .invalidRequest:
            return MidgarCreditsError.invalidResponse
        case .cancelled:
            return CancellationError()
        case .tokenUnavailable:
            return MidgarCreditsError.identityUnavailable
        }
    }
}
