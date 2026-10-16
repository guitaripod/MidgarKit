import Foundation
import Testing
@testable import MidgarCore

private let publicJWKPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("../../services/config/keys/public.jwk")
    .standardized.path

@Suite struct ConfigKeyTests {
    private struct JWK: Decodable {
        let kid: String
        let x: String
        let y: String
        let kty: String
        let crv: String
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: publicJWKPath)))
    func embeddedProductionKeyMatchesPublicJWK() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: publicJWKPath))
        let jwk = try JSONDecoder().decode(JWK.self, from: data)
        #expect(jwk.kty == "EC")
        #expect(jwk.crv == "P-256")
        #expect(MidgarConfigKey.production == MidgarConfigKey(kid: jwk.kid, x: jwk.x, y: jwk.y))
        #expect(MidgarConfigKey.pinned.contains(MidgarConfigKey.production))
    }

    #if canImport(CryptoKit)
    @Test func productionKeyIsAValidCurvePoint() {
        #expect(MidgarConfigKey.production.publicKey != nil)
    }

    @Test func offCurveKeyIsRejected() {
        let bad = MidgarConfigKey(kid: "bad", x: "AAAA", y: "AAAA")
        #expect(bad.publicKey == nil)
    }
    #endif
}
