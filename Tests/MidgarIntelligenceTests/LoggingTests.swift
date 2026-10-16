import Foundation
import Testing
import MidgarIntelligence

@Suite struct LoggingTests {
    private let secret = "my private diary entry zebra-quartz-7731"

    private func assertClean(_ lines: [String]) {
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(!line.contains("zebra-quartz-7731"))
            #expect(!line.contains("diary"))
            #expect(!line.contains("secret instructions"))
        }
    }

    @Test func cloudCallsNeverLogPromptOrCompletionText() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, "{\"content\":\"completion zebra-quartz-7731\",\"model\":\"m\",\"credits_charged\":2,\"usage\":{}}")])
        let sink = LogSink()
        let model = MidgarCloudModel(client: host.client(logger: sink.logger), logger: sink.logger)
        _ = try await model.respond(to: MidgarPrompt(instructions: "secret instructions", text: secret))
        assertClean(sink.lines)
    }

    @Test func failedCloudCallsNeverLogPromptText() async {
        let host = CloudTestHost()
        host.enqueue([.json(402, "{\"error\":{\"message\":\"\(secret)\"}}")])
        let sink = LogSink()
        let model = MidgarCloudModel(client: host.client(logger: sink.logger), logger: sink.logger)
        _ = try? await model.respond(to: MidgarPrompt(text: secret))
        assertClean(sink.lines)
    }

    @Test func routerDecisionsNeverLogPromptText() async throws {
        let sink = LogSink()
        let failing = FakeModel(failure: MidgarIntelligenceError.onDeviceUnavailable(.modelNotReady))
        let router = MidgarIntelligence(onDevice: failing, cloud: FakeModel(route: .cloud, answer: secret), logger: sink.logger)
        _ = try await router.respond(to: MidgarPrompt(instructions: "secret instructions", text: secret))
        _ = try await collect(router.streamResponse(to: MidgarPrompt(instructions: "secret instructions", text: secret)))
        assertClean(sink.lines)
        #expect(sink.lines.contains { $0.contains("route=cloud") })
    }
}
