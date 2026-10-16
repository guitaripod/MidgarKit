import Foundation

/// The verified payload of a config JWS.
struct MidgarConfigDocument: Sendable, Equatable, Decodable {
    let app: String
    let version: Int
    let issuedAt: Int?
    let values: [String: MidgarConfigValue]
    let kill: Set<String>
    let minVersion: String?

    private enum CodingKeys: String, CodingKey {
        case app, version, issuedAt, values, kill, minVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        version = try container.decode(Int.self, forKey: .version)
        issuedAt = try container.decodeIfPresent(Int.self, forKey: .issuedAt)
        minVersion = try? container.decodeIfPresent(String.self, forKey: .minVersion)
        let rawValues = try container.decodeIfPresent([String: LenientConfigValue].self, forKey: .values) ?? [:]
        values = rawValues.compactMapValues(\.value)
        let rawKill = try container.decodeIfPresent([String: LenientConfigValue].self, forKey: .kill) ?? [:]
        kill = Set(rawKill.filter { $0.value.value == .bool(true) }.keys)
    }
}

/// Unpadded base64url, the encoding of every compact JWS segment.
enum Base64URL {
    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    /// Nil when the text holds anything outside the base64url alphabet, padding included.
    static func decode(_ text: String) -> Data? {
        guard text.allSatisfy({ alphabet.contains($0) }), text.count % 4 != 1 else {
            return nil
        }
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        return Data(base64Encoded: base64)
    }
}
