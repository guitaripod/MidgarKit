import Foundation
import Testing
@testable import MidgarCore

private struct Pong: Codable, Sendable, Equatable {
    let ok: Bool
    let version: String
}

private struct Note: Codable, Sendable, Equatable {
    let name: String
}

private actor TokenCounter {
    private(set) var calls = 0
    private let tokens: [String?]

    init(tokens: [String?]) {
        self.tokens = tokens
    }

    func next() -> String? {
        let token = tokens[min(calls, tokens.count - 1)]
        calls += 1
        return token
    }
}

@Suite struct MidgarHTTPClientTests {
    @Test func sendsIdentifyingHeadersAndQuery() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host)

        let request = MidgarRequest(
            service: "catalog",
            path: "apps/42",
            query: [URLQueryItem(name: "limit", value: "5")]
        )
        let _: Pong = try await client.send(request)

        let sent = try #require(host.requests.first)
        #expect(sent.method == "GET")
        #expect(sent.url.path == "/v1/catalog/apps/42")
        #expect(sent.url.query == "limit=5")
        #expect(sent.headers["X-App-ID"] == "app-test")
        #expect(sent.headers["User-Agent"] == "TestApp/1.0 MidgarKit/4.0.0")
        #expect(sent.headers["Accept"] == "application/json")
        #expect(sent.headers["Authorization"] == nil)
        let requestID = try #require(sent.headers["X-Midgar-Request-Id"])
        #expect(UUID(uuidString: requestID) != nil)
    }

    @Test func requestIDIsFreshForEveryRequest() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}"), .json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host)

        let _: Pong = try await client.send(MidgarRequest(service: "health"))
        let _: Pong = try await client.send(MidgarRequest(service: "health"))

        let ids = host.requests.compactMap { $0.headers["X-Midgar-Request-Id"] }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    @Test func injectsBearerTokenFromProvider() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host, tokenProvider: { "secret-token" })

        let _: Pong = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.first?.headers["Authorization"] == "Bearer secret-token")
    }

    @Test(arguments: [nil, ""] as [String?])
    func omitsAuthorizationWhenProviderHasNoToken(token: String?) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host, tokenProvider: { token })

        let _: Pong = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.first?.headers["Authorization"] == nil)
    }

    @Test func asksTheTokenProviderOnEveryAttempt() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), .json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let counter = TokenCounter(tokens: ["first", "second"])
        let client = makeStubClient(host, tokenProvider: { await counter.next() })

        let _: Pong = try await client.send(MidgarRequest(service: "health"))

        let sent = host.requests
        #expect(sent.count == 2)
        #expect(sent.first?.headers["Authorization"] == "Bearer first")
        #expect(sent.last?.headers["Authorization"] == "Bearer second")
    }

    @Test func encodesJSONBody() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host)

        let _: Pong = try await client.send(
            MidgarRequest(service: "intelligence", path: "notes", method: .post, body: Note(name: "wave"))
        )

        let sent = try #require(host.requests.first)
        #expect(sent.method == "POST")
        #expect(sent.headers["Content-Type"] == "application/json")
        let body = try JSONDecoder().decode(Note.self, from: try #require(sent.body))
        #expect(body == Note(name: "wave"))
    }

    @Test func callerHeadersCannotOverrideReservedOnes() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host)

        let _: Pong = try await client.send(
            MidgarRequest(service: "health", headers: ["X-App-ID": "spoofed", "X-Trace": "kept"])
        )

        let sent = try #require(host.requests.first)
        #expect(sent.headers["X-App-ID"] == "app-test")
        #expect(sent.headers["X-Trace"] == "kept")
    }

    @Test func decodesTheSuccessBody() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"4.0.0\"}")])
        let client = makeStubClient(host)

        let pong: Pong = try await client.send(MidgarRequest(service: "health"))

        #expect(pong == Pong(ok: true, version: "4.0.0"))
    }

    @Test func undecodableSuccessBodyThrowsDecoding() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "not json at all")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.send(MidgarRequest(service: "health")) as Pong }

        guard case .decoding = error else {
            Issue.record("expected .decoding, got \(String(describing: error))")
            return
        }
    }

    @Test func sendRawReturnsBodyAndResponse() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "raw-bytes", headers: ["X-Custom": "yes"])])
        let client = makeStubClient(host)

        let (data, response) = try await client.sendRaw(MidgarRequest(service: "flaccy", path: "file"))

        #expect(String(decoding: data, as: UTF8.self) == "raw-bytes")
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "X-Custom") == "yes")
    }

    @Test func unencodableBodyThrowsInvalidRequestWithoutSending() async throws {
        let host = HTTPTestHost()
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Double.nan))
        }

        guard case .invalidRequest = error else {
            Issue.record("expected .invalidRequest, got \(String(describing: error))")
            return
        }
        #expect(host.requests.isEmpty)
    }

    @Test func cancelledBeforeStartMapsToCancelled() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"ok\":true,\"version\":\"1\"}")])
        let client = makeStubClient(host)

        let task = Task { () async throws -> Pong in
            try await client.send(MidgarRequest(service: "health"))
        }
        task.cancel()
        let result = await task.result

        guard case .failure(let thrown) = result, let error = thrown as? MidgarHTTPError else {
            Issue.record("expected a MidgarHTTPError cancellation, got \(result)")
            return
        }
        #expect(error == .cancelled)
    }

    @Test func emptyServiceNameIsInvalid() async throws {
        let host = HTTPTestHost()
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "")) }

        #expect(error == .invalidRequest("The service name or path cannot form a URL."))
        #expect(host.requests.isEmpty)
    }

    @Test func urlBuildingPercentEncodesAndKeepsBasePath() throws {
        let base = try #require(URL(string: "https://example.test/gateway/"))
        let url = try #require(
            MidgarRequest(service: "catalog", path: "/apps//a b/c?d#e/").url(relativeTo: base)
        )
        #expect(url.absoluteString == "https://example.test/gateway/v1/catalog/apps/a%20b/c%3Fd%23e")

        let root = try #require(MidgarRequest(service: "health").url(relativeTo: base))
        #expect(root.absoluteString == "https://example.test/gateway/v1/health")
    }

    @Test func serviceWithSlashIsRejected() {
        #expect(MidgarRequest(service: "a/b").url(relativeTo: MidgarHTTPConfiguration.defaultBaseURL) == nil)
    }

    @Test func defaultConfigurationTargetsTheGateway() {
        let configuration = MidgarHTTPConfiguration(appID: "pay-day")

        #expect(configuration.baseURL.absoluteString == "https://api.midgarcorp.cc")
        #expect(configuration.timeout == 30)
        #expect(configuration.userAgent.hasSuffix(" MidgarKit/\(MidgarKitVersion.current)"))
    }
}
