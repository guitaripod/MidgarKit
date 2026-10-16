import Foundation

/// Why a config document was not accepted. Cases carry no document text, so they are safe to log.
public enum MidgarConfigError: Error, Sendable, Equatable {
    case malformed
    case unsupportedHeader
    case unknownKey
    case badSignature
    case wrongApp
    case rolledBack(version: Int, lastGood: Int)
    case unsupportedPlatform

    var logName: String {
        switch self {
        case .malformed: "malformed"
        case .unsupportedHeader: "unsupportedHeader"
        case .unknownKey: "unknownKey"
        case .badSignature: "badSignature"
        case .wrongApp: "wrongApp"
        case .rolledBack(let version, let lastGood): "rolledBack(version=\(version) lastGood=\(lastGood))"
        case .unsupportedPlatform: "unsupportedPlatform"
        }
    }
}
