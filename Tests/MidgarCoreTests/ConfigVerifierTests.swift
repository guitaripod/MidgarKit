#if canImport(CryptoKit)
import CryptoKit
import Foundation
import Testing
@testable import MidgarCore

@Suite struct ConfigVerifierTests {
    private let signer = ConfigSigner()

    private func verifier(keys: [MidgarConfigKey]? = nil) -> MidgarConfigVerifier {
        MidgarConfigVerifier(keys: keys ?? [signer.pinnedKey], slug: configTestSlug)
    }

    @Test func validDocumentVerifies() throws {
        let jws = try signer.jws(version: 7, values: ["a": 1, "b": "x"], kill: ["ai"], minVersion: "2.0")
        let document = try verifier().verify(jws)
        #expect(document.version == 7)
        #expect(document.values == ["a": .int(1), "b": .string("x")])
        #expect(document.kill == ["ai"])
        #expect(document.minVersion == "2.0")
    }

    @Test(arguments: [
        #"{"minVersion": 2}"#,
        #"{"minVersion": {"x": 1}}"#,
        #"{"kill": ["ai"]}"#,
        #"{"kill": "ai"}"#,
        #"{"kill": {"ai": "yes"}}"#,
        #"{"kill": {"ai": 1}}"#
    ])
    func aWrongTypeForMinVersionOrKillRejectsTheDocument(overridesJSON: String) throws {
        let overrides = try #require(JSONSerialization.jsonObject(with: Data(overridesJSON.utf8)) as? [String: Any])
        let jws = try signer.jws(version: 7, payloadOverrides: overrides)
        #expect(throws: MidgarConfigError.malformed) { try verifier().verify(jws) }
    }

    @Test func aFalseKillEntryIsNotKilled() throws {
        let jws = try signer.jws(version: 7, payloadOverrides: ["kill": ["ai": false, "share": true]])
        #expect(try verifier().verify(jws).kill == ["share"])
    }

    @Test func tamperedPayloadFailsSignature() throws {
        let jws = try signer.jws(version: 7, values: ["a": 1])
        let parts = jws.split(separator: ".").map(String.init)
        let forged = try signer.jws(version: 8, values: ["a": 2]).split(separator: ".").map(String.init)
        let swapped = [parts[0], forged[1], parts[2]].joined(separator: ".")
        #expect(throws: MidgarConfigError.badSignature) { try verifier().verify(swapped) }
    }

    @Test func signatureFromAnotherKeyFails() throws {
        let other = ConfigSigner()
        let jws = try other.jws()
        #expect(throws: MidgarConfigError.badSignature) { try verifier().verify(jws) }
    }

    @Test func truncatedSignatureFails() throws {
        let jws = try signer.jws()
        let shortened = String(jws.dropLast(4))
        #expect(throws: MidgarConfigError.badSignature) { try verifier().verify(shortened) }
    }

    @Test func unknownKidFails() throws {
        let jws = try signer.jws(headerKid: "someone-else")
        #expect(throws: MidgarConfigError.unknownKey) { try verifier().verify(jws) }
    }

    @Test func wrongAlgorithmFails() throws {
        let jws = try signer.jws(alg: "HS256")
        #expect(throws: MidgarConfigError.unsupportedHeader) { try verifier().verify(jws) }
    }

    @Test func wrongTypeFails() throws {
        let jws = try signer.jws(typ: "JWT")
        #expect(throws: MidgarConfigError.unsupportedHeader) { try verifier().verify(jws) }
    }

    @Test func otherAppsDocumentFails() throws {
        let jws = try signer.jws(app: "psywave")
        #expect(throws: MidgarConfigError.wrongApp) { try verifier().verify(jws) }
    }

    @Test(arguments: ["", "a.b", "a.b.c.d", "!!!.###.$$$", "e30.e30."])
    func malformedInputFails(_ text: String) {
        #expect(throws: MidgarConfigError.self) { try verifier().verify(text) }
    }

    @Test func rotationAcceptsEitherPinnedKey() throws {
        let next = ConfigSigner(kid: "test-key-2")
        let keys = [signer.pinnedKey, next.pinnedKey]
        #expect(try verifier(keys: keys).verify(next.jws(version: 3)).version == 3)
        #expect(try verifier(keys: keys).verify(signer.jws(version: 4)).version == 4)
    }

    @Test func nonScalarValuesAreDropped() throws {
        let jws = try signer.jws(values: ["nested": ["a": 1], "list": [1, 2], "ok": true])
        #expect(try verifier().verify(jws).values == ["ok": .bool(true)])
    }
}
#else
import Testing
@testable import MidgarCore

@Suite struct ConfigVerifierFailClosedTests {
    @Test func everyDocumentIsRejectedWithoutCryptoKit() {
        let verifier = MidgarConfigVerifier(keys: MidgarConfigKey.pinned, slug: "solar-beam")
        #expect(throws: MidgarConfigError.self) { try verifier.verify("e30.e30.AAAA") }
    }
}
#endif
