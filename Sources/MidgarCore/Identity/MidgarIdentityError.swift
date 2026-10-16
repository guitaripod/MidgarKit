import Foundation

/// Every way a ``MidgarIdentity`` call can fail. Nothing stored changes when one is thrown, except where a flow documents it.
public enum MidgarIdentityError: Error, Sendable, Equatable, LocalizedError, MidgarTransientError {
    case http(MidgarHTTPError)
    case keychain(status: Int32)
    case attestation(MidgarAttestationError)
    case corruptSharedItem
    case malformedResponse
    case credentialPendingSync
    case credentialUnavailable

    /// True for failures that a later attempt can fix without any other change: offline, timeout, rate limiting, server errors, Apple's attestation service being unreachable and a shared credential that other devices have not synced yet.
    public var isTransient: Bool {
        switch self {
        case .http(let error):
            return error.isTransient
        case .attestation(.unavailable), .credentialPendingSync:
            return true
        case .keychain, .attestation, .corruptSharedItem, .malformedResponse, .credentialUnavailable:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .http(let error):
            return error.errorDescription
        case .keychain:
            return NSLocalizedString(
                "Your Midgar ID could not be saved or read on this device.",
                bundle: .module,
                comment: "Shown when the keychain refuses to store or return the Midgar ID"
            )
        case .attestation:
            return NSLocalizedString(
                "This device could not be verified. Try again later.",
                bundle: .module,
                comment: "Shown when App Attest fails while the Midgar ID is being set up"
            )
        case .corruptSharedItem:
            return NSLocalizedString(
                "Your saved Midgar ID could not be read. Update the app and try again.",
                bundle: .module,
                comment: "Shown when the shared Midgar ID in the keychain has a format this app version cannot read"
            )
        case .malformedResponse:
            return NSLocalizedString(
                "The server response could not be read.",
                bundle: .module,
                comment: "Shown when a Midgar server response does not match what the app expects"
            )
        case .credentialPendingSync:
            return NSLocalizedString(
                "Your Midgar ID is still syncing from your other devices. Try again later.",
                bundle: .module,
                comment: "Shown when the shared Midgar ID credential on this device was rejected and may be waiting for iCloud Keychain to deliver a newer one"
            )
        case .credentialUnavailable:
            return NSLocalizedString(
                "Your Midgar ID could not be confirmed on this device. Restart the app and try again.",
                bundle: .module,
                comment: "Shown when an account change needs the Midgar ID credential and this device has none stored"
            )
        }
    }

    /// Converts whatever a flow threw into the public error type.
    static func normalizing(_ error: any Error) -> any Error {
        switch error {
        case let identity as MidgarIdentityError:
            return identity
        case let http as MidgarHTTPError:
            return MidgarIdentityError.http(http)
        case let keychain as MidgarKeychainError:
            return MidgarIdentityError.keychain(status: keychain.status)
        case let attestation as MidgarAttestationError:
            return MidgarIdentityError.attestation(attestation)
        case is CancellationError:
            return error
        default:
            return MidgarIdentityError.attestation(.failed)
        }
    }
}
