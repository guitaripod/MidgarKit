import Foundation

/// Why an App Attest call failed, in the terms the identity flows act on.
public enum MidgarAttestationError: Error, Sendable, Equatable {
    case unsupported
    case invalidKey
    case unavailable
    case failed
}

/// App Attest as the identity flows use it. Every hash is SHA-256: of the UTF-8 challenge for an attestation and of the UTF-8 refresh token for an assertion.
public protocol MidgarAttestation: Sendable {
    var isSupported: Bool { get }

    /// A new key id. Throws ``MidgarAttestationError/unsupported`` where the device cannot attest.
    func generateKey() async throws -> String

    /// The attestation object for a key that has not been attested before.
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data

    /// An assertion by an attested key. Throws ``MidgarAttestationError/invalidKey`` when the key no longer exists, as after a reinstall or restore.
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

/// The attestation of platforms and processes without App Attest: Linux, Macs before macOS 27, most app extensions and the Simulator.
public struct MidgarUnsupportedAttestation: MidgarAttestation {
    public init() {}

    public var isSupported: Bool { false }

    public func generateKey() async throws -> String {
        throw MidgarAttestationError.unsupported
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        throw MidgarAttestationError.unsupported
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        throw MidgarAttestationError.unsupported
    }
}

#if canImport(DeviceCheck)
import DeviceCheck

/// App Attest through `DCAppAttestService.shared`.
public struct MidgarAppAttestation: MidgarAttestation {
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws -> String {
        do {
            return try await DCAppAttestService.shared.generateKey()
        } catch {
            throw MidgarAttestationError(deviceCheck: error)
        }
    }

    public func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
        } catch {
            throw MidgarAttestationError(deviceCheck: error)
        }
    }

    public func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
        } catch {
            throw MidgarAttestationError(deviceCheck: error)
        }
    }
}

extension MidgarAttestationError {
    /// Maps a DeviceCheck failure: a missing key, an unsupported device, Apple's service being unreachable, or anything else.
    init(deviceCheck error: any Error) {
        guard let failure = error as? DCError else {
            self = .failed
            return
        }
        switch failure.code {
        case .invalidKey:
            self = .invalidKey
        case .featureUnsupported:
            self = .unsupported
        case .serverUnavailable:
            self = .unavailable
        default:
            self = .failed
        }
    }
}
#endif
