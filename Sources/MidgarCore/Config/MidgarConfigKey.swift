import Foundation

/// A pinned ES256 public key that may sign config documents: its `kid` and the base64url P-256 coordinates from the JWK.
public struct MidgarConfigKey: Sendable, Equatable {
    public let kid: String
    public let x: String
    public let y: String

    public init(kid: String, x: String, y: String) {
        self.kid = kid
        self.x = x
        self.y = y
    }
}

extension MidgarConfigKey {
    /// The production signing key, copied from `services/config/keys/public.jwk`. A test fails when the two drift apart.
    public static let production = MidgarConfigKey(
        kid: "cfg-2026-10-16-1a23a3ed",
        x: "LEDOCsK_0qR1d_517oGC7m2nf4tYZ6zw0MY3bCnL4Es",
        y: "9h8hS-I0LuGeLbzoT4Y_cr6AYzgwe25cnz6zFOisjsE"
    )

    /// Every key an app accepts. Key rotation ships a second entry here for the overlap period.
    public static let pinned: [MidgarConfigKey] = [production]
}
