#if canImport(CryptoKit)
import CryptoKit
import Foundation
@testable import MidgarCore

let configTestSlug = "solar-beam"
let configTestKid = "test-key-1"

/// Signs config documents the way `services/config/scripts/configJws.mjs` does, with a key made for the test.
struct ConfigSigner: Sendable {
    let privateKey = P256.Signing.PrivateKey()
    let kid: String

    init(kid: String = configTestKid) {
        self.kid = kid
    }

    var pinnedKey: MidgarConfigKey {
        MidgarConfigKey(kid: kid, publicKey: privateKey.publicKey)
    }

    func jws(
        app: String = configTestSlug,
        version: Int = 100,
        values: [String: Any] = [:],
        kill: [String] = [],
        minVersion: String? = nil,
        alg: String = "ES256",
        typ: String = "midgar-config+jwt",
        headerKid: String? = nil
    ) throws -> String {
        var payload: [String: Any] = [
            "app": app,
            "version": version,
            "issuedAt": version,
            "values": values,
            "kill": Dictionary(uniqueKeysWithValues: kill.map { ($0, true) })
        ]
        if let minVersion {
            payload["minVersion"] = minVersion
        }
        let header: [String: Any] = ["alg": alg, "typ": typ, "kid": headerKid ?? kid]
        return try sign(header: header, payload: payload)
    }

    func sign(header: [String: Any], payload: [String: Any]) throws -> String {
        let input = "\(try encode(header)).\(try encode(payload))"
        let signature = try privateKey.signature(for: Data(input.utf8))
        return "\(input).\(Self.base64URL(signature.rawRepresentation))"
    }

    private func encode(_ object: [String: Any]) throws -> String {
        Self.base64URL(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

func configBody(_ jws: String) -> String {
    "{\"config\":\"\(jws)\"}"
}

final class ConfigLogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.withLock { storage }
    }

    func append(_ line: String) {
        lock.withLock { storage.append(line) }
    }
}

final class ConfigTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date.addTimeInterval(seconds) }
    }
}

struct ConfigFixture: Sendable {
    let signer = ConfigSigner()
    let host = HTTPTestHost()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("midgar-config-\(UUID().uuidString)")
    let logs = ConfigLogSink()
    let clock = ConfigTestClock()

    func store(
        defaults: [String: MidgarConfigValue] = [:],
        keys: [MidgarConfigKey]? = nil,
        interval: TimeInterval = 900
    ) -> MidgarConfigStore {
        let sink = logs
        let clock = clock
        return MidgarConfigStore(
            slug: configTestSlug,
            client: makeStubClient(host),
            defaults: defaults,
            keys: keys ?? [signer.pinnedKey],
            cacheDirectory: directory,
            minimumRefreshInterval: interval,
            now: { clock.now },
            logger: { sink.append($0) }
        )
    }

    var cacheFile: URL {
        directory.appendingPathComponent("config-\(configTestSlug).jws")
    }

    func ok(_ jws: String) -> StubReply {
        .json(200, configBody(jws), headers: ["ETag": "\"x\""])
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
