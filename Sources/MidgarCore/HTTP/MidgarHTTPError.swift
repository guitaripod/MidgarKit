import Foundation

/// Every way a call through `MidgarHTTPClient` can fail. Each case has a user-facing description.
public enum MidgarHTTPError: Error, Sendable, Equatable, LocalizedError {
    case offline
    case timeout
    case unauthorized
    case paymentRequired
    case rateLimited(retryAfter: TimeInterval?)
    case notFound
    case server(status: Int, code: String?, message: String)
    case decoding(String)
    case invalidRequest(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .offline:
            return String(
                localized: "You appear to be offline. Check your connection and try again.",
                bundle: .module,
                comment: "Shown when Midgar cannot reach its servers because the device has no usable network"
            )
        case .timeout:
            return String(
                localized: "The request timed out. Try again.",
                bundle: .module,
                comment: "Shown when a request to Midgar's servers took longer than the allowed time"
            )
        case .unauthorized:
            return String(
                localized: "Your session has expired. Sign in again.",
                bundle: .module,
                comment: "Shown when Midgar rejects the signed-in credentials"
            )
        case .paymentRequired:
            return String(
                localized: "This needs more credits or an active subscription.",
                bundle: .module,
                comment: "Shown when an action needs credits or a subscription the user does not have"
            )
        case .rateLimited:
            return String(
                localized: "Too many requests. Try again in a moment.",
                bundle: .module,
                comment: "Shown when Midgar's servers ask the app to slow down"
            )
        case .notFound:
            return String(
                localized: "The requested item could not be found.",
                bundle: .module,
                comment: "Shown when the item a request asked for does not exist on Midgar's servers"
            )
        case .server:
            return String(
                localized: "Midgar could not complete the request. Try again later.",
                bundle: .module,
                comment: "Shown when Midgar's servers fail with an error the app cannot act on"
            )
        case .decoding:
            return String(
                localized: "The server response could not be read.",
                bundle: .module,
                comment: "Shown when a Midgar server response does not match what the app expects"
            )
        case .invalidRequest:
            return String(
                localized: "The request could not be prepared.",
                bundle: .module,
                comment: "Shown when the app cannot build a request to Midgar's servers"
            )
        case .cancelled:
            return String(
                localized: "The request was cancelled.",
                bundle: .module,
                comment: "Shown when a request to Midgar's servers was cancelled before it finished"
            )
        }
    }
}
