import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Checks a compact JWS against the pinned keys and the app slug. Verification fails closed: anything unexpected throws.
struct MidgarConfigVerifier: Sendable {
    static let algorithm = "ES256"
    static let type = "midgar-config+jwt"

    let keys: [MidgarConfigKey]
    let slug: String

    private struct Header: Decodable {
        let alg: String?
        let typ: String?
        let kid: String?
    }

    /// Order: shape, header (`alg`, `typ`, `kid`), signature, payload, then the app slug. Nothing in the payload is read before the signature verifies.
    func verify(_ jws: String) throws(MidgarConfigError) -> MidgarConfigDocument {
        let parts = jws.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            throw .malformed
        }
        let header = try decodeHeader(parts[0])
        guard header.alg == Self.algorithm, header.typ == Self.type else {
            throw .unsupportedHeader
        }
        guard let key = keys.first(where: { $0.kid == header.kid }) else {
            throw .unknownKey
        }
        try verifySignature(of: "\(parts[0]).\(parts[1])", encodedSignature: parts[2], key: key)
        let document = try decodePayload(parts[1])
        guard document.app == slug else {
            throw .wrongApp
        }
        return document
    }

    private func decodeHeader(_ segment: String) throws(MidgarConfigError) -> Header {
        guard let data = Base64URL.decode(segment), let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw .malformed
        }
        return header
    }

    private func decodePayload(_ segment: String) throws(MidgarConfigError) -> MidgarConfigDocument {
        guard let data = Base64URL.decode(segment), let document = try? JSONDecoder().decode(MidgarConfigDocument.self, from: data) else {
            throw .malformed
        }
        return document
    }

    #if canImport(CryptoKit)
    /// ES256 signatures are the raw 64-byte r||s over the ASCII `header.payload` text.
    private func verifySignature(of signingInput: String, encodedSignature: String, key: MidgarConfigKey) throws(MidgarConfigError) {
        guard let publicKey = key.publicKey,
              let raw = Base64URL.decode(encodedSignature),
              raw.count == 64,
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: raw),
              publicKey.isValidSignature(signature, for: Data(signingInput.utf8))
        else {
            throw .badSignature
        }
    }
    #else
    /// Platforms without CryptoKit cannot verify, so they never accept a document and apps run on compiled defaults.
    private func verifySignature(of signingInput: String, encodedSignature: String, key: MidgarConfigKey) throws(MidgarConfigError) {
        throw .unsupportedPlatform
    }
    #endif
}

#if canImport(CryptoKit)
extension MidgarConfigKey {
    /// The key as a CryptoKit public key, or nil when the coordinates are not two 32-byte values on the curve.
    var publicKey: P256.Signing.PublicKey? {
        guard let xBytes = Base64URL.decode(x), let yBytes = Base64URL.decode(y), xBytes.count == 32, yBytes.count == 32 else {
            return nil
        }
        return try? P256.Signing.PublicKey(x963Representation: Data([0x04]) + xBytes + yBytes)
    }

    /// Pins an existing CryptoKit public key. Tests use it to sign documents with a key generated on the spot.
    public init(kid: String, publicKey: P256.Signing.PublicKey) {
        let point = publicKey.x963Representation
        self.init(
            kid: kid,
            x: Self.base64URL(point.subdata(in: 1..<33)),
            y: Self.base64URL(point.subdata(in: 33..<65))
        )
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
