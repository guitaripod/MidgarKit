import Foundation
import Testing
@testable import MidgarCore

private struct Empty: Codable, Sendable {}

@Suite struct MidgarHTTPErrorTests {
    @Test func unauthorizedMapsFrom401() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, "{\"error\":{\"code\":\"unauthorized\",\"message\":\"no\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }
        #expect(error == .unauthorized(code: "unauthorized"))
    }

    @Test func paymentRequiredMapsFrom402() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(402, "{}")])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .paymentRequired(code: nil))
    }

    @Test func notFoundMapsFrom404() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(404, "{\"error\":{\"code\":\"not_found\",\"message\":\"Not here\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }
        #expect(error == .notFound(code: "not_found"))
    }

    @Test func rateLimitedWithoutRetryAfterMapsFrom429() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(429, "{\"error\":{\"code\":\"rate_limited\",\"message\":\"slow\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .rateLimited(retryAfter: nil, code: "rate_limited"))
    }

    @Test func rateLimitedCarriesRetryAfterSeconds() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(429, "{}", headers: ["Retry-After": "12"])])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .rateLimited(retryAfter: 12, code: nil))
    }

    @Test func gatewayEnvelopeIsParsed() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(400, "{\"error\":{\"code\":\"unknown_app_id\",\"message\":\"Unknown X-App-ID \\\"x\\\".\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }

        #expect(error == .server(status: 400, code: "unknown_app_id", message: "Unknown X-App-ID \"x\"."))
    }

    @Test func legacyStringErrorIsParsed() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(400, "{\"error\":\"Bad input from mako\"}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "intelligence")) }

        #expect(error == .server(status: 400, code: nil, message: "Bad input from mako"))
    }

    @Test func legacyMessageShapeIsParsed() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(422, "{\"message\":\"Content blocked\"}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "intelligence")) }

        #expect(error == .server(status: 422, code: nil, message: "Content blocked"))
    }

    @Test func nestedMakoEnvelopeKeepsCodeAndMessage() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(422, "{\"error\":{\"message\":\"Truncated\",\"type\":\"generation_error\",\"code\":\"truncated\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "intelligence")) }

        #expect(error == .server(status: 422, code: "truncated", message: "Truncated"))
    }

    @Test func emptyEnvelopeFallsBackToStatusText() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(400, "{\"error\":{\"code\":\"\",\"message\":\"\"}}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "intelligence")) }

        #expect(error == .server(status: 400, code: nil, message: "HTTP 400"))
    }

    @Test func nonJSONFailureFallsBackToStatusText() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(500, "<html>boom</html>")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }

        #expect(error == .server(status: 500, code: nil, message: "HTTP 500"))
    }

    @Test func exhaustedGatewayFailureKeepsItsStatus() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(502, "{}"), .json(502, "{}"), .json(502, "{}")])
        let client = makeStubClient(host)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }

        #expect(error == .server(status: 502, code: nil, message: "HTTP 502"))
    }

    @Test func notConnectedMapsToOffline() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.notConnectedToInternet)])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .offline)
    }

    @Test func timedOutMapsToTimeout() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.timedOut)])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .timeout)
    }

    @Test func urlCancelledMapsToCancelled() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.cancelled)])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Empty()))
        }

        #expect(error == .cancelled)
    }

    @Test func transportMappingCoversUnknownErrors() {
        #expect(MidgarHTTPError(transport: CancellationError()) == .cancelled)
        #expect(MidgarHTTPError(transport: URLError(.cannotFindHost)) == .offline)
        #expect(MidgarHTTPError(transport: URLError(.timedOut)) == .timeout)
        #expect(MidgarHTTPError(transport: NSError(domain: "x", code: 1)) == .offline)
    }

    @Test func onlyTransientFailuresAreRetryable() {
        let retryable: [MidgarHTTPError] = [
            .offline, .timeout, .rateLimited(retryAfter: nil, code: nil),
            .server(status: 502, code: nil, message: ""),
            .server(status: 503, code: nil, message: ""),
            .server(status: 504, code: nil, message: ""),
        ]
        let fatal: [MidgarHTTPError] = [
            .unauthorized(code: nil), .paymentRequired(code: nil), .notFound(code: nil), .cancelled, .tokenUnavailable(isTransient: true), .decoding(""), .invalidRequest(""),
            .server(status: 400, code: nil, message: ""), .server(status: 500, code: nil, message: ""),
        ]
        #expect(retryable.allSatisfy { $0.isRetryable })
        #expect(fatal.allSatisfy { !$0.isRetryable })
    }

    @Test func everyCaseHasADescriptionAndLogName() {
        let cases: [MidgarHTTPError] = [
            .offline, .timeout, .unauthorized(code: nil), .paymentRequired(code: nil), .rateLimited(retryAfter: 5, code: nil), .notFound(code: nil),
            .server(status: 500, code: "c", message: "m"), .decoding("d"), .invalidRequest("i"), .cancelled,
            .tokenUnavailable(isTransient: false),
        ]
        for error in cases {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(!error.logName.isEmpty)
        }
        #expect(MidgarHTTPError.server(status: 500, code: "c", message: "secret text").logName == "server")
    }
}
