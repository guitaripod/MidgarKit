import Foundation

/// A failure that says whether trying again later can fix it without any other change.
public protocol MidgarTransientError: Error {
    var isTransient: Bool { get }
}

/// Every way a call through `MidgarHTTPClient` can fail. Each case has a user-facing description.
///
/// The cases for 401, 402, 404 and 429 carry the `code` of the server's error envelope (nil when the body had none); ``serverCode`` reads it for every case that has one. Match them without their payload (`case .unauthorized:`) to ignore it. Switch with `@unknown default`: cases are added in minor releases.
public enum MidgarHTTPError: Error, Sendable, Equatable, LocalizedError, MidgarTransientError {
    case offline
    case timeout
    case unauthorized(code: String?)
    case paymentRequired(code: String?)
    case rateLimited(retryAfter: TimeInterval?, code: String?)
    case notFound(code: String?)
    case server(status: Int, code: String?, message: String)
    case decoding(String)
    case invalidRequest(String)
    case cancelled
    case tokenUnavailable(isTransient: Bool)

    /// The envelope's error code for any case that carries one.
    public var serverCode: String? {
        switch self {
        case .unauthorized(let code), .paymentRequired(let code), .notFound(let code), .rateLimited(_, let code):
            return code
        case .server(_, let code, _):
            return code
        case .offline, .timeout, .decoding, .invalidRequest, .cancelled, .tokenUnavailable:
            return nil
        }
    }

    /// True for failures that a later attempt can fix without any other change: offline, timeout, rate limiting, server errors and a token provider that failed transiently.
    public var isTransient: Bool {
        switch self {
        case .offline, .timeout, .rateLimited:
            return true
        case .server(let status, _, _):
            return status >= 500
        case .tokenUnavailable(let isTransient):
            return isTransient
        case .unauthorized, .paymentRequired, .notFound, .decoding, .invalidRequest, .cancelled:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .offline:
            return NSLocalizedString(
                "You appear to be offline. Check your connection and try again.",
                bundle: .module,
                comment: "Shown when Midgar cannot reach its servers because the device has no usable network"
            )
        case .timeout:
            return NSLocalizedString(
                "The request timed out. Try again.",
                bundle: .module,
                comment: "Shown when a request to Midgar's servers took longer than the allowed time"
            )
        case .unauthorized:
            return NSLocalizedString(
                "Your session has expired. Sign in again.",
                bundle: .module,
                comment: "Shown when Midgar rejects the signed-in credentials"
            )
        case .paymentRequired:
            return NSLocalizedString(
                "This needs more credits or an active subscription.",
                bundle: .module,
                comment: "Shown when an action needs credits or a subscription the user does not have"
            )
        case .rateLimited:
            return NSLocalizedString(
                "Too many requests. Try again in a moment.",
                bundle: .module,
                comment: "Shown when Midgar's servers ask the app to slow down"
            )
        case .notFound:
            return NSLocalizedString(
                "The requested item could not be found.",
                bundle: .module,
                comment: "Shown when the item a request asked for does not exist on Midgar's servers"
            )
        case .server:
            return NSLocalizedString(
                "Midgar could not complete the request. Try again later.",
                bundle: .module,
                comment: "Shown when Midgar's servers fail with an error the app cannot act on"
            )
        case .decoding:
            return NSLocalizedString(
                "The server response could not be read.",
                bundle: .module,
                comment: "Shown when a Midgar server response does not match what the app expects"
            )
        case .invalidRequest:
            return NSLocalizedString(
                "The request could not be prepared.",
                bundle: .module,
                comment: "Shown when the app cannot build a request to Midgar's servers"
            )
        case .cancelled:
            return NSLocalizedString(
                "The request was cancelled.",
                bundle: .module,
                comment: "Shown when a request to Midgar's servers was cancelled before it finished"
            )
        case .tokenUnavailable:
            return NSLocalizedString(
                "Your Midgar ID is not ready yet. Try again in a moment.",
                bundle: .module,
                comment: "Shown when a request could not be sent because the app could not get an access token for the Midgar ID"
            )
        }
    }
}
