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
    let challenge: String
    let assertion: String?
    let credential: String?
}

struct DeleteBody: Encodable, Sendable {
    let assertion: String?
    let clientData: String?
    let credential: String?
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

/// The value of the per-app keychain item while the app has a session. `midgarId` is the resolved ID the server last returned for this session. `deleteSentAt` is set before an account deletion is sent and cleared by the next session the service issues, so a deletion whose answer was lost can be told from one that never left.
struct StoredSession: Codable, Sendable, Equatable {
    let refreshToken: String
    let keyId: String?
    let midgarId: String
    var deleteSentAt: Date? = nil
}

/// The value of the per-app keychain item while the shared credential is rejected but the identity exists, which usually means another device rotated it and keychain sync has not delivered the new one. `credentialDigest` names the credential that failed, so a newer one is tried at once.
struct PendingSync: Codable, Sendable, Equatable {
    let firstFailure: Date
    let lastAttempt: Date
    let credentialDigest: String
}

/// What the per-app keychain item holds.
enum PerAppItem: Sendable, Equatable {
    case session(StoredSession)
    case pendingSync(PendingSync)
}

/// An access token with what the client needs to know about it.
struct LiveSession: Sendable, Equatable {
    let accessToken: String
    let expiresAt: Date
    let tier: MidgarIdentityTier
    let midgarId: String

    /// Reads `att` from the token and takes the expiry from the reply's `expiresIn`, counted from `now` on the device clock. The token's absolute `exp` is on the server's clock, so a device clock that is ahead would see a fresh token as expired and refresh on every call; `exp` is used only when the reply has no usable `expiresIn`. A token that cannot be read falls back to the `unverified` tier, so a stored refresh token is never lost to a parsing problem.
    init(reply: SessionReply, now: Date) {
        let claims = MidgarAccessClaims(token: reply.accessToken)
        accessToken = reply.accessToken
        if reply.expiresIn > 0 {
            expiresAt = now.addingTimeInterval(reply.expiresIn)
        } else {
            expiresAt = claims?.expiresAt ?? now
        }
        tier = claims?.tier ?? .unverified
        midgarId = reply.midgarId
    }

    func isFresh(at now: Date, margin: TimeInterval) -> Bool {
        expiresAt.timeIntervalSince(now) > margin
    }
}
