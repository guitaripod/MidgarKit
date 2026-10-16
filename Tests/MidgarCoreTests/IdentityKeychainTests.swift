import Foundation
import Testing
@testable import MidgarCore
#if canImport(CryptoKit)
import CryptoKit
#endif

@Suite struct IdentityKeychainTests {
    @Test func inMemoryKeychainWritesReadsAndDeletesPerSlot() throws {
        let keychain = MidgarInMemoryKeychain()
        let slot = MidgarKeychainSlot.session(appID: "a")
        #expect(try keychain.read(slot) == nil)
        try keychain.write(Data("1".utf8), to: slot)
        #expect(try keychain.read(slot) == Data("1".utf8))
        #expect(try keychain.read(.session(appID: "b")) == nil)
        #expect(try keychain.writeIfAbsent(Data("2".utf8), to: slot) == false)
        #expect(try keychain.writeIfAbsent(Data("2".utf8), to: .shared) == true)
        try keychain.delete(slot)
        try keychain.delete(slot)
        #expect(try keychain.read(slot) == nil)
        #expect(try keychain.read(.shared) == Data("2".utf8))
    }

    #if canImport(Security)
    @Test func theSharedSlotIsASynchronizableItemInTheTeamAccessGroup() {
        let keychain = MidgarSecItemKeychain()
        let query = keychain.identifyingQuery(for: .shared)
        let attributes = keychain.creationAttributes(for: .shared, data: Data("x".utf8))

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "cc.midgarcorp.identity")
        #expect(query[kSecAttrAccount as String] as? String == "midgar-id")
        #expect(query[kSecAttrAccessGroup as String] as? String == "P4DQK6SRKR.cc.midgarcorp.shared")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == true)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(attributes[kSecValueData as String] as? Data == Data("x".utf8))
        #if os(macOS)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #endif
    }

    @Test func theAccessGroupIsConfigurable() {
        #expect(MidgarSecItemKeychain(accessGroup: "T.other").identifyingQuery(for: .shared)[kSecAttrAccessGroup as String] as? String == "T.other")
        #expect(MidgarSecItemKeychain(accessGroup: nil).identifyingQuery(for: .shared)[kSecAttrAccessGroup as String] == nil)
    }

    @Test func theSessionSlotIsADeviceOnlyItemNamedAfterTheApp() {
        let keychain = MidgarSecItemKeychain()
        let query = keychain.identifyingQuery(for: .session(appID: "solar-beam"))
        let attributes = keychain.creationAttributes(for: .session(appID: "solar-beam"), data: Data("x".utf8))

        #expect(query[kSecAttrService as String] as? String == "cc.midgarcorp.identity.session")
        #expect(query[kSecAttrAccount as String] as? String == "solar-beam")
        #expect(query[kSecAttrAccessGroup as String] == nil)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #if os(macOS)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #endif
    }
    #endif

    @Test func portableSHA256MatchesThePublishedVectors() {
        func hex(_ text: String) -> String {
            PortableSHA256.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        #expect(hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    @Test func portableSHA256HandlesEveryPaddingBoundary() {
        for length in [0, 1, 54, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000] {
            let input = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
            #expect(PortableSHA256.hash(input) == MidgarDigest.sha256(input))
            #if canImport(CryptoKit)
            #expect(PortableSHA256.hash(input) == Data(SHA256.hash(data: input)))
            #endif
        }
    }

    @Test func accessClaimsReadExpiryAndTierWithoutVerifying() {
        let claims = MidgarAccessClaims(token: makeJWT(expiresAt: identityEpoch, tier: "development"))
        #expect(claims?.expiresAt == identityEpoch)
        #expect(claims?.tier == .development)
        #expect(MidgarAccessClaims(token: "not-a-jwt") == nil)
        #expect(MidgarAccessClaims(token: makeJWT(expiresAt: identityEpoch, tier: "future-tier"))?.tier == nil)
    }
}
