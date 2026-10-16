import Foundation
import Testing
import MidgarIntelligence

@Suite struct CloudModelTests {
    private let okBody = """
    {"content":"Hello there","model":"gemini-3-flash-preview","credits_charged":4,\
    "usage":{"prompt_tokens":5,"output_tokens":7,"total_tokens":12}}
    """

    private func sentJSON(_ host: CloudTestHost) throws -> [String: Any] {
        let body = try #require(host.requests.first?.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func sendsOneChatCompletionThroughTheGateway() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, okBody)])
        let model = MidgarCloudModel(client: host.client())
        let completion = try await model.respond(to: MidgarPrompt(instructions: "Be brief", text: "Hi"))

        #expect(completion == MidgarCompletion(text: "Hello there", route: .cloud, model: "gemini-3-flash-preview", creditsCharged: 4))
        let request = try #require(host.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path == "/v1/intelligence/v1/run/chat.completion")
        #expect(request.headers["Authorization"] == "Bearer token-abc")
        #expect(request.headers["X-App-ID"] == "app-test")
        #expect(request.headers["Content-Type"] == "application/json")
        let json = try sentJSON(host)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "Be brief"], ["role": "user", "content": "Hi"]])
        #expect(json["images"] == nil)
        #expect(json["model"] == nil)
    }

    @Test func pinsTheModelAndSendsImagesAsDataURLs() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, okBody)])
        let model = MidgarCloudModel(client: host.client(), model: "claude-haiku-4-5")
        let image = MidgarPromptImage(data: Data([1, 2, 3]), mediaType: "image/png")
        _ = try await model.respond(to: MidgarPrompt(text: "What is this?", images: [image]))

        let json = try sentJSON(host)
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["images"] as? [String] == ["data:image/png;base64,AQID"])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 1)
    }

    @Test func aPaymentRequiredReplyNeedsCredits() async {
        let host = CloudTestHost()
        host.enqueue([.json(402, "{\"error\":{\"code\":\"insufficient_credits\",\"message\":\"no\"}}")])
        let model = MidgarCloudModel(client: host.client())
        await #expect(throws: MidgarIntelligenceError.needsCredits) {
            try await model.respond(to: MidgarPrompt(text: "Hi"))
        }
    }

    @Test func aRateLimitCarriesRetryAfter() async {
        let host = CloudTestHost()
        host.enqueue([.json(429, "{}", headers: ["Retry-After": "60"])])
        let model = MidgarCloudModel(client: host.client())
        await #expect(throws: MidgarIntelligenceError.rateLimited(retryAfter: 60)) {
            try await model.respond(to: MidgarPrompt(text: "Hi"))
        }
        #expect(host.requests.count == 1)
    }

    @Test func otherFailuresKeepTheGatewayError() async {
        let host = CloudTestHost()
        host.enqueue([.json(500, "{\"error\":{\"code\":\"internal_error\",\"message\":\"boom\"}}")])
        let model = MidgarCloudModel(client: host.client())
        await #expect(throws: MidgarIntelligenceError.cloudFailed(.server(status: 500, code: "internal_error", message: "boom"))) {
            try await model.respond(to: MidgarPrompt(text: "Hi"))
        }
    }

    @Test func anEmptyAnswerIsAnError() async {
        let host = CloudTestHost()
        host.enqueue([.json(200, "{\"content\":\"\",\"model\":\"m\",\"credits_charged\":0,\"usage\":{}}")])
        let model = MidgarCloudModel(client: host.client())
        await #expect(throws: MidgarIntelligenceError.emptyResponse) {
            try await model.respond(to: MidgarPrompt(text: "Hi"))
        }
    }

    @Test func streamingYieldsTheWholeAnswerAsOneDelta() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, okBody)])
        let model = MidgarCloudModel(client: host.client())
        #expect(try await collect(model.streamResponse(to: MidgarPrompt(text: "Hi"))) == ["Hello there"])
        #expect(host.requests.count == 1)
    }

    @Test func streamingReportsTypedErrors() async {
        let host = CloudTestHost()
        host.enqueue([.json(402, "{}")])
        let model = MidgarCloudModel(client: host.client())
        await #expect(throws: MidgarIntelligenceError.needsCredits) {
            try await collect(model.streamResponse(to: MidgarPrompt(text: "Hi")))
        }
    }

    @Test func readsTheBalanceAndWeeklyBuckets() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, """
        {"user_id":"u","balance":1250,"weekly":{"dream":{"limit":3,"remaining":2,"resets_at":"2026-10-19T00:00:00Z"}},\
        "last_updated":"2026-10-16T10:00:00Z"}
        """)])
        let balance = try await MidgarCloudModel(client: host.client()).balance()
        #expect(balance.credits == 1250)
        let bucket = try #require(balance.weekly["dream"])
        #expect(bucket.limit == 3)
        #expect(bucket.remaining == 2)
        #expect(bucket.resetsAt == Date(timeIntervalSince1970: 1_792_368_000))
        let request = try #require(host.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.path == "/v1/intelligence/v1/credits/balance")
    }

    @Test func aBalanceWithoutBucketsHasNone() async throws {
        let host = CloudTestHost()
        host.enqueue([.json(200, "{\"balance\":5}")])
        let balance = try await MidgarCloudModel(client: host.client()).balance()
        #expect(balance == MidgarCreditBalance(credits: 5, weekly: [:]))
    }
}
