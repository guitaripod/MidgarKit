import Foundation
import MidgarCore

/// Every way a ``MidgarLanguageModel`` call can fail. Cancellation is never wrapped: it surfaces as `CancellationError`.
public enum MidgarIntelligenceError: Error, Sendable, Equatable, LocalizedError {
    /// The `intelligence` kill switch is on: no route may answer.
    case disabled
    /// The `intelligence.cloud` kill switch is on and the prompt needs the cloud.
    case cloudDisabled
    /// The cloud answered 402: the caller has no credits or allowance left.
    case needsCredits
    case rateLimited(retryAfter: TimeInterval?)
    /// The on-device model cannot answer and the cloud may not.
    case onDeviceUnavailable(MidgarOnDeviceUnavailableReason)
    /// The on-device model failed and the cloud may not answer instead. `errorType` is the failing type's name, never message text.
    case onDeviceFailed(errorType: String)
    /// The on-device model declined the prompt (a guardrail or a refusal). The cloud is never asked instead: a refusal is an answer, not an outage.
    case onDeviceRefused
    /// The on-device stream rewrote text it had already delivered, so its snapshots no longer add up to one answer. Text that reached the caller cannot be taken back, so the stream stops with this error instead of ending as if it were complete.
    case onDeviceOutputRewritten
    /// The cloud call failed for a reason other than credits or rate limits.
    case cloudFailed(MidgarHTTPError)
    /// The model returned no text.
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .disabled, .cloudDisabled:
            return NSLocalizedString(
                "This feature is turned off for now. Try again later.",
                bundle: .module,
                comment: "Shown when an AI feature was switched off remotely"
            )
        case .needsCredits:
            return NSLocalizedString(
                "This needs more credits or an active subscription.",
                bundle: .module,
                comment: "Shown when an AI request needs credits or a subscription the user does not have"
            )
        case .rateLimited:
            return NSLocalizedString(
                "Too many requests. Try again in a moment.",
                bundle: .module,
                comment: "Shown when the AI service asks the app to slow down"
            )
        case .onDeviceUnavailable:
            return NSLocalizedString(
                "On-device intelligence is not available on this device right now.",
                bundle: .module,
                comment: "Shown when the on-device model cannot answer and the cloud is not allowed to"
            )
        case .onDeviceFailed, .onDeviceRefused, .onDeviceOutputRewritten, .cloudFailed, .emptyResponse:
            return NSLocalizedString(
                "The AI request could not be completed. Try again.",
                bundle: .module,
                comment: "Shown when an AI request failed"
            )
        }
    }
}
