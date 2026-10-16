import Foundation
import Testing
@testable import MidgarCore

private enum SignalsLiveGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MIDGAR_LIVE_SIGNALS"] == "1"
    }
}

private struct SignalsAnswer: Decodable, Sendable {
    let accepted: Int
    let dropped: Int
}

@Suite(.tags(.live), .enabled(if: SignalsLiveGate.isEnabled, "Set MIDGAR_LIVE_SIGNALS=1 to send one app.launch to api.midgarcorp.cc"))
struct SignalsLiveTests {
    @Test func productionAcceptsOneAppLaunchEvent() async throws {
        let client = MidgarHTTPClient(configuration: MidgarHTTPConfiguration(appID: "dream-eater"))
        let event = try #require(MidgarSignalEvent(name: "app.launch", props: [:]))
        let request = MidgarRequest(
            service: "signals",
            path: "events",
            method: .post,
            headers: ["X-Platform": MidgarSignalsPlatform.current, "X-App-Version": "1.0"],
            body: MidgarSignalBatch(events: [event]),
            neverRetries: true
        )

        let (data, response) = try await client.sendRaw(request)

        #expect(response.statusCode == 202)
        let answer = try JSONDecoder().decode(SignalsAnswer.self, from: data)
        #expect(answer.accepted == 1)
        #expect(answer.dropped == 0)
    }
}
