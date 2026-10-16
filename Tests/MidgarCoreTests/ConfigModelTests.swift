import Foundation
import Testing
@testable import MidgarCore

@Suite struct ConfigModelTests {
    private func document(
        values: [String: MidgarConfigValue] = [:],
        kill: Set<String> = [],
        minVersion: String? = nil
    ) throws -> MidgarConfigDocument {
        var payload: [String: Any] = [
            "app": "solar-beam",
            "version": 5,
            "values": values.mapValues { value -> Any in
                switch value {
                case .bool(let flag): flag
                case .int(let number): number
                case .double(let number): number
                case .string(let text): text
                }
            },
            "kill": Dictionary(uniqueKeysWithValues: kill.map { ($0, true) })
        ]
        if let minVersion {
            payload["minVersion"] = minVersion
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(MidgarConfigDocument.self, from: data)
    }

    @Test func documentValuesBeatDefaults() throws {
        let config = MidgarConfig(
            document: try document(values: ["flag": true, "limit": 9, "ratio": 0.25, "title": "doc"]),
            defaults: ["flag": false, "limit": 3, "ratio": 1.0, "title": "compiled"]
        )
        #expect(config.bool("flag", default: false))
        #expect(config.int("limit", default: 0) == 9)
        #expect(config.double("ratio", default: 0) == 0.25)
        #expect(config.string("title", default: "") == "doc")
        #expect(config.version == 5)
        #expect(config.isFromDocument)
    }

    @Test func missingKeysUseCompiledDefaultsThenArgument() throws {
        let config = MidgarConfig(
            document: try document(),
            defaults: ["flag": true, "limit": 3, "ratio": 1.5, "title": "compiled"]
        )
        #expect(config.bool("flag", default: false))
        #expect(config.int("limit", default: 0) == 3)
        #expect(config.double("ratio", default: 0) == 1.5)
        #expect(config.string("title", default: "") == "compiled")
        #expect(config.bool("absent", default: true))
        #expect(config.int("absent", default: 42) == 42)
    }

    @Test func wrongTypedValuesFallBack() throws {
        let config = MidgarConfig(
            document: try document(values: ["flag": "yes", "limit": "ten", "ratio": true, "title": 4]),
            defaults: ["flag": true, "limit": 3, "ratio": 1.5, "title": "compiled"]
        )
        #expect(config.bool("flag", default: false))
        #expect(config.int("limit", default: 0) == 3)
        #expect(config.double("ratio", default: 0) == 1.5)
        #expect(config.string("title", default: "") == "compiled")
    }

    @Test func integersWidenToDoubles() throws {
        let config = MidgarConfig(document: try document(values: ["ratio": 2]), defaults: [:])
        #expect(config.double("ratio", default: 0) == 2)
    }

    @Test func defaultsOnlySnapshot() {
        let config = MidgarConfig(defaults: ["flag": true])
        #expect(config.bool("flag", default: false))
        #expect(config.version == nil)
        #expect(!config.isFromDocument)
        #expect(!config.isKilled("anything"))
        #expect(!config.requiresUpdate(currentVersion: "0.0.1"))
    }

    @Test func killSwitchIsHonoured() throws {
        let config = MidgarConfig(document: try document(kill: ["ai", "share"]), defaults: [:])
        #expect(config.isKilled("ai"))
        #expect(config.isKilled("share"))
        #expect(!config.isKilled("export"))
    }

    @Test(arguments: [
        ("1.9.9", "1.10.0", true),
        ("1.10.0", "1.9.9", false),
        ("1.2.3", "1.2.3", false),
        ("1.2", "1.2.0", false),
        ("1", "1.0.1", true),
        ("2.0.0", "1.99.99", false),
        ("4.0.0-beta", "4.0.0", false),
        ("3.9.1", "4", true)
    ])
    func minVersionComparison(current: String, minimum: String, update: Bool) throws {
        let config = MidgarConfig(document: try document(minVersion: minimum), defaults: [:])
        #expect(config.requiresUpdate(currentVersion: current) == update)
    }

    @Test func unreadableVersionsNeverDemandUpdate() throws {
        let config = MidgarConfig(document: try document(minVersion: "2.0"), defaults: [:])
        #expect(!config.requiresUpdate(currentVersion: "garbage"))
        #expect(!config.requiresUpdate(currentVersion: ""))
        let broken = MidgarConfig(document: try document(minVersion: "x.y"), defaults: [:])
        #expect(!broken.requiresUpdate(currentVersion: "1.0"))
    }
}
