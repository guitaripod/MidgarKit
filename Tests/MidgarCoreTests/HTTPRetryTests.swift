import Foundation
import Testing
@testable import MidgarCore

private let okBody = StubReply.json(200, "{\"ok\":true}")

@Suite struct MidgarHTTPRetryTests {
    @Test func getRetriesServerUnavailableThenSucceeds() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), okBody])
        let client = makeStubClient(host)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.count == 2)
    }

    @Test(arguments: [502, 503, 504])
    func getRetriesGatewayFailures(status: Int) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(status, "{}"), okBody])
        let client = makeStubClient(host)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.count == 2)
    }

    @Test func postIsNeverRetried() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), okBody])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Note()))
        }

        #expect(error == .server(status: 503, code: nil, message: "HTTP 503"))
        #expect(host.requests.count == 1)
    }

    @Test func postWithIdempotentFlagRetries() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(502, "{}"), .json(504, "{}"), okBody])
        let client = makeStubClient(host)

        let (_, response) = try await client.sendRaw(
            MidgarRequest(service: "intelligence", method: .post, body: Note(), idempotent: true)
        )

        #expect(response.statusCode == 200)
        #expect(host.requests.count == 3)
    }

    @Test(arguments: [MidgarHTTPMethod.put, .delete, .get, .head])
    func idempotentMethodsRetryByDefault(method: MidgarHTTPMethod) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), .json(200, "{}")])
        let client = makeStubClient(host)

        _ = try await client.sendRaw(MidgarRequest(service: "catalog", path: "x", method: method))

        #expect(host.requests.count == 2)
    }

    @Test(arguments: [MidgarHTTPMethod.post, .patch])
    func nonIdempotentMethodsDoNotRetryByDefault(method: MidgarHTTPMethod) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), .json(200, "{}")])
        let client = makeStubClient(host)

        _ = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog", path: "x", method: method)) }

        #expect(host.requests.count == 1)
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422, 500])
    func clientAndOtherServerErrorsAreNeverRetried(status: Int) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(status, "{}"), okBody])
        let client = makeStubClient(host)

        _ = await thrownError { try await client.sendRaw(MidgarRequest(service: "catalog")) }

        #expect(host.requests.count == 1)
    }

    @Test func rateLimitedGetHonoursRetryAfterSeconds() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(429, "{}", headers: ["Retry-After": "2"]), okBody])
        let sleeps = SleepRecorder()
        let client = makeStubClient(host, sleeps: sleeps)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(await sleeps.durations == [2])
        #expect(host.requests.count == 2)
    }

    @Test func serviceUnavailableHonoursRetryAfterSeconds() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}", headers: ["Retry-After": "7"]), okBody])
        let sleeps = SleepRecorder()
        let client = makeStubClient(host, sleeps: sleeps)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(await sleeps.durations == [7])
    }

    @Test func retryAfterHTTPDateInThePastWaitsNoTime() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}", headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"]), okBody])
        let sleeps = SleepRecorder()
        let client = makeStubClient(host, sleeps: sleeps)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(await sleeps.durations == [0])
    }

    @Test func retryAfterBeyondTheCeilingStopsRetrying() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(429, "{}", headers: ["Retry-After": "3600"]), okBody])
        let sleeps = SleepRecorder()
        let client = makeStubClient(host, sleeps: sleeps)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "health")) }

        #expect(error == .rateLimited(retryAfter: 3600))
        #expect(host.requests.count == 1)
        #expect(await sleeps.durations.isEmpty)
    }

    @Test func exhaustedAttemptsSurfaceTheLastError() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), .json(503, "{}"), .json(503, "{}"), okBody])
        let sleeps = SleepRecorder()
        let client = makeStubClient(host, sleeps: sleeps)

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "health")) }

        #expect(error == .server(status: 503, code: nil, message: "HTTP 503"))
        #expect(host.requests.count == 3)
        #expect(await sleeps.durations.count == 2)
    }

    @Test func offlineIsRetriedForIdempotentRequests() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.notConnectedToInternet), .failing(.networkConnectionLost), okBody])
        let client = makeStubClient(host)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.count == 3)
    }

    @Test func timeoutIsRetriedForIdempotentRequests() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.timedOut), okBody])
        let client = makeStubClient(host)

        let _: [String: Bool] = try await client.send(MidgarRequest(service: "health"))

        #expect(host.requests.count == 2)
    }

    @Test func networkErrorIsNotRetriedForPost() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.notConnectedToInternet), okBody])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Note()))
        }

        #expect(error == .offline)
        #expect(host.requests.count == 1)
    }

    @Test func rateLimitedPostIsNotRetried() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(429, "{}"), okBody])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", method: .post, body: Note()))
        }

        #expect(error == .rateLimited(retryAfter: nil))
        #expect(host.requests.count == 1)
    }

    @Test func cancellationDuringBackoffMapsToCancelled() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), okBody])
        let configuration = MidgarHTTPConfiguration(
            baseURL: host.baseURL,
            appID: "app-test",
            session: makeStubSession()
        )
        let client = MidgarHTTPClient(configuration: configuration, retryPolicy: .testing) { _ in
            throw CancellationError()
        }

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "health")) }

        #expect(error == .cancelled)
        #expect(host.requests.count == 1)
    }

    @Test func standardPolicyAllowsThreeAttempts() {
        #expect(MidgarRetryPolicy.standard.maximumAttempts == 3)
        #expect(MidgarRetryPolicy.standard.maximumRetryAfter == 60)
    }
}

private struct Note: Codable, Sendable, Equatable {
    var name: String = "note"
}
