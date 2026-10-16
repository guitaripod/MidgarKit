import Foundation
import Testing
@testable import MidgarCore

extension Tag {
    @Tag static var live: Tag
}

private enum MidgarLiveGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MIDGAR_LIVE"] == "1"
    }
}

private struct GatewayHealth: Decodable, Sendable {
    let ok: Bool
    let version: String
    let services: [String]
}

@Suite(.tags(.live), .enabled(if: MidgarLiveGate.isEnabled, "Set MIDGAR_LIVE=1 to call api.midgarcorp.cc"))
struct MidgarHTTPLiveTests {
    @Test func liveHealthCheckDecodesFromTheGateway() async throws {
        let client = MidgarHTTPClient(
            configuration: MidgarHTTPConfiguration(appID: "midgarkit-tests")
        )

        let health: GatewayHealth = try await client.send(MidgarRequest(service: "health"))

        #expect(health.ok)
        #expect(!health.version.isEmpty)
        #expect(health.services.contains("catalog"))
    }
}
