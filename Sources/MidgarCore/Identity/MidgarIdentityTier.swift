import Foundation

/// How strongly the identity was attested, from the access token's `att` claim.
public enum MidgarIdentityTier: String, Sendable, Equatable, CaseIterable {
    case appAttest = "app_attest"
    case development
    case unverified
}

/// The claims the client reads from an access token. The token is not verified here: the server verifies it on every call, and the client only needs to know when to refresh.
struct MidgarAccessClaims: Sendable, Equatable {
    let expiresAt: Date?
    let tier: MidgarIdentityTier?

    init?(token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payload = Self.decodeBase64URL(String(parts[1])),
              let claims = try? JSONDecoder().decode(Payload.self, from: payload)
        else {
            return nil
        }
        expiresAt = claims.exp.map { Date(timeIntervalSince1970: $0) }
        tier = claims.att.flatMap(MidgarIdentityTier.init(rawValue:))
    }

    private struct Payload: Decodable {
        let exp: Double?
        let att: String?
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}
