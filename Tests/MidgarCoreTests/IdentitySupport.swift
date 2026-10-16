import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MidgarCore

let identityEpoch = Date(timeIntervalSince1970: 1_800_000_000)

/// Records App Attest calls and fails on demand. Every field is read and written only inside `lock`, which is what makes the unchecked conformance sound.
final class FakeAttestation: MidgarAttestation, @unchecked Sendable {
    private let lock = NSLock()
    private var supported: Bool
    private var keyCounter = 0
    private var assertionCounter = 0
    private var generatedKeys: [String] = []
    private var attestedHashes: [(keyID: String, hash: Data)] = []
    private var assertedHashes: [(keyID: String, hash: Data)] = []
    private var generateFailure: MidgarAttestationError?
    private var attestFailure: MidgarAttestationError?
    private var assertionFailure: MidgarAttestationError?

    init(supported: Bool) {
        self.supported = supported
    }

    var isSupported: Bool { lock.withLock { supported } }
    var keys: [String] { lock.withLock { generatedKeys } }
    var attestations: [(keyID: String, hash: Data)] { lock.withLock { attestedHashes } }
    var assertions: [(keyID: String, hash: Data)] { lock.withLock { assertedHashes } }

    func failGenerate(with error: MidgarAttestationError?) { lock.withLock { generateFailure = error } }
    func failAttest(with error: MidgarAttestationError?) { lock.withLock { attestFailure = error } }
    func failAssertion(with error: MidgarAttestationError?) { lock.withLock { assertionFailure = error } }

    func generateKey() async throws -> String {
        try lock.withLock {
            if let generateFailure { throw generateFailure }
            keyCounter += 1
            let keyID = "key-\(keyCounter)"
            generatedKeys.append(keyID)
            return keyID
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try lock.withLock {
            if let attestFailure { throw attestFailure }
            attestedHashes.append((keyID, clientDataHash))
            return Data("attestation-of-\(keyID)".utf8)
        }
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try lock.withLock {
            if let assertionFailure { throw assertionFailure }
            assertionCounter += 1
            assertedHashes.append((keyID, clientDataHash))
            return Data("assertion-\(assertionCounter)-by-\(keyID)".utf8)
        }
    }
}

/// A clock the test moves by hand. `current` is read and written only inside `lock`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = identityEpoch) {
        current = start
    }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Collects every log line from the identity flows and the HTTP client. The line arrays are touched only inside `lock`.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var infoLines: [String] = []
    private var warningLines: [String] = []

    var info: [String] { lock.withLock { infoLines } }
    var warnings: [String] { lock.withLock { warningLines } }
    var all: [String] { lock.withLock { infoLines + warningLines } }

    func recordInfo(_ line: String) { lock.withLock { infoLines.append(line) } }
    func recordWarning(_ line: String) { lock.withLock { warningLines.append(line) } }
}

/// Wraps a keychain to simulate another Midgar app writing the shared item while a mint is in flight. Its stored properties are immutable and the base keychain locks its own state.
final class RacingKeychain: MidgarKeychain, @unchecked Sendable {
    let base: MidgarInMemoryKeychain
    private let rival: Data

    init(base: MidgarInMemoryKeychain, rival: SharedIdentity) throws {
        self.base = base
        self.rival = try JSONEncoder().encode(rival)
    }

    func read(_ slot: MidgarKeychainSlot) throws -> Data? { try base.read(slot) }
    func write(_ data: Data, to slot: MidgarKeychainSlot) throws { try base.write(data, to: slot) }
    func delete(_ slot: MidgarKeychainSlot) throws { try base.delete(slot) }

    func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool {
        try base.write(rival, to: slot)
        return false
    }
}

final class UnreadableSharedKeychain: MidgarKeychain, @unchecked Sendable {
    let base: MidgarInMemoryKeychain

    init(base: MidgarInMemoryKeychain) {
        self.base = base
    }

    func read(_ slot: MidgarKeychainSlot) throws -> Data? { slot == .shared ? nil : try base.read(slot) }
    func write(_ data: Data, to slot: MidgarKeychainSlot) throws { try base.write(data, to: slot) }
    func delete(_ slot: MidgarKeychainSlot) throws { try base.delete(slot) }
    func writeIfAbsent(_ data: Data, to slot: MidgarKeychainSlot) throws -> Bool { false }
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// An unsigned-looking JWT carrying the claims the client reads.
func makeJWT(expiresAt: Date, tier: String = "unverified", subject: String = "sub") -> String {
    let header = base64URL(Data(#"{"alg":"ES256","typ":"JWT","kid":"k"}"#.utf8))
    let claims = #"{"sub":"\#(subject)","att":"\#(tier)","exp":\#(Int(expiresAt.timeIntervalSince1970))}"#
    return "\(header).\(base64URL(Data(claims.utf8))).c2ln"
}

func sessionJSON(
    midgarId: String,
    accessToken: String,
    refreshToken: String,
    extra: [String: Any] = [:]
) -> String {
    var object: [String: Any] = [
        "midgarId": midgarId, "accessToken": accessToken, "refreshToken": refreshToken, "expiresIn": 3600
    ]
    object.merge(extra) { _, new in new }
    return jsonText(object)
}

func jsonText(_ object: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

func errorJSON(_ code: String) -> String {
    jsonText(["error": ["code": code, "message": "m"]])
}

func bodyObject(_ request: CapturedRequest) -> [String: Any] {
    guard let body = request.body,
          let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    else {
        return [:]
    }
    return object
}

func bodyText(_ request: CapturedRequest) -> String {
    request.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
}

/// One identity under test with its stub server, keychain, fake App Attest, clock and captured logs.
struct IdentityHarness: Sendable {
    let host: HTTPTestHost
    let keychain: MidgarInMemoryKeychain
    let attestation: FakeAttestation
    let clock: TestClock
    let logs: LogCapture
    let identity: MidgarIdentity
    let store: MidgarIdentityStore

    static let appID = "app-test"
    static let bundleID = "com.example.test"

    init(
        attested: Bool = false,
        shared: SharedIdentity? = nil,
        session: StoredSession? = nil,
        keychainOverride: (@Sendable (MidgarInMemoryKeychain) throws -> any MidgarKeychain)? = nil
    ) throws {
        let host = HTTPTestHost()
        let keychain = MidgarInMemoryKeychain()
        let attestation = FakeAttestation(supported: attested)
        let clock = TestClock()
        let logs = LogCapture()
        let store = MidgarIdentityStore(keychain: keychain, appID: Self.appID)
        if let shared { try store.writeShared(shared) }
        if let session { try store.writeSession(session) }
        let effective: any MidgarKeychain = try keychainOverride?(keychain) ?? keychain
        self.host = host
        self.keychain = keychain
        self.attestation = attestation
        self.clock = clock
        self.logs = logs
        self.store = store
        self.identity = MidgarIdentity(
            appID: Self.appID,
            bundleID: Self.bundleID,
            http: makeStubClient(host, logger: { logs.recordInfo($0) }),
            keychain: effective,
            attestation: attestation,
            clock: { clock.now },
            log: MidgarIdentityLogger(info: { logs.recordInfo($0) }, warning: { logs.recordWarning($0) })
        )
    }

    func enqueue(_ replies: StubReply...) {
        host.enqueue(replies)
    }

    var paths: [String] {
        host.requests.map { "\($0.method) \($0.url.path)" }
    }

    func storedShared() throws -> SharedIdentity? {
        try store.readShared()
    }

    func storedSession() throws -> StoredSession? {
        try store.readSession()
    }
}

func freshToken(_ tier: String = "unverified", lifetime: TimeInterval = 3600) -> String {
    makeJWT(expiresAt: identityEpoch.addingTimeInterval(lifetime), tier: tier)
}
