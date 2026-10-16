import Foundation

struct ChallengeReply: Decodable, Sendable {
    let challenge: String
}

struct MintAttestedBody: Encodable, Sendable {
    let keyId: String
    let attestation: String
    let challenge: String
    let bundleId: String
}

struct MintUnverifiedBody: Encodable, Sendable {
    let bundleId: String
}

struct AttachBody: Encodable, Sendable {
    let midgarId: String
    let credential: String
    let bundleId: String
    let keyId: String?
    let attestation: String?
    let challenge: String?
}

struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
    let assertion: String?
    let clientData: String?
}

struct LinkAppleBody: Encodable, Sendable {
    let identityToken: String
}

struct SessionReply: Decodable, Sendable {
    let midgarId: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
}

struct MintReply: Decodable, Sendable {
    let session: SessionReply
    let credential: String

    private enum CodingKeys: String, CodingKey {
        case credential
    }

    init(from decoder: any Decoder) throws {
        session = try SessionReply(from: decoder)
        credential = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .credential)
    }
}

struct LinkAppleReply: Decodable, Sendable {
    let midgarId: String
    let merged: Bool
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let credential: String?
}

/// The value of the shared keychain item.
struct SharedIdentity: Codable, Sendable, Equatable {
    let midgarId: String
    let credential: String
}

/// The value of the per-app keychain item. `midgarId` is the resolved ID the server last returned for this session.
struct StoredSession: Codable, Sendable, Equatable {
    let refreshToken: String
    let keyId: String?
    let midgarId: String
}

/// An access token with what the client needs to know about it.
struct LiveSession: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date
    let tier: MidgarIdentityTier
    let midgarId: String

    /// Reads `exp` and `att` from the token. A token that cannot be read falls back to the reply's `expiresIn` and the `unverified` tier, so a stored refresh token is never lost to a parsing problem.
    init(reply: SessionReply, now: Date) {
        let claims = MidgarAccessClaims(token: reply.accessToken)
        accessToken = reply.accessToken
        expiresAt = claims?.expiresAt ?? now.addingTimeInterval(reply.expiresIn)
        tier = claims?.tier ?? .unverified
        midgarId = reply.midgarId
    }

    func isFresh(at now: Date, margin: TimeInterval) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }
}
