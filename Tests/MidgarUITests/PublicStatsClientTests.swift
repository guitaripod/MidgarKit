import Foundation
import Testing
@testable import MidgarUI

/// What the stub saw and what it answers next. The lock guards both fields, which is what makes the unchecked conformance sound.
final class StatsStub: @unchecked Sendable {
    static let shared = StatsStub()

    private let lock = NSLock()
    private var reply: Result<(Int, Data), URLError> = .failure(URLError(.notConnectedToInternet))
    private var seen: [URLRequest] = []

    func answer(_ reply: Result<(Int, Data), URLError>) {
        lock.withLock {
            self.reply = reply
            seen = []
        }
    }

    func next(for request: URLRequest) -> Result<(Int, Data), URLError> {
        lock.withLock {
            seen.append(request)
            return reply
        }
    }

    var requests: [URLRequest] {
        lock.withLock { seen }
    }
}

final class StatsStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch StatsStub.shared.next(for: request) {
        case .success(let (status, body)):
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: nil) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct PublicStatsClientTests {
    private func client() -> MidgarPublicStatsClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatsStubProtocol.self]
        return MidgarPublicStatsClient(session: URLSession(configuration: configuration))
    }

    @Test func asksThePublicURLOnceAndReadsTheAnswer() async throws {
        StatsStub.shared.answer(.success((200, Data(publicStatsJSON.utf8))))

        let stats = try await client().loadStats()

        #expect(stats.latestWeek(for: "flaccy")?.weeklyActiveInstalls == .exactly(12))
        #expect(StatsStub.shared.requests.count == 1)
        #expect(StatsStub.shared.requests.first?.url?.absoluteString == "https://api.midgarcorp.cc/v1/ops/public/stats")
        #expect(StatsStub.shared.requests.first?.httpMethod == "GET")
    }

    @Test func theRequestCarriesNoIdentifierAndNoCookie() async throws {
        StatsStub.shared.answer(.success((200, Data(publicStatsJSON.utf8))))

        _ = try await client().loadStats()

        let request = try #require(StatsStub.shared.requests.first)
        let headers = Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() })
        #expect(headers.isDisjoint(with: ["authorization", "x-app-id", "x-midgar-token", "cookie", "x-platform", "x-app-version"]))
        #expect(request.httpBody == nil)
        #expect(!request.httpShouldHandleCookies)
    }

    @Test func theRequestGivesUpQuickly() async throws {
        StatsStub.shared.answer(.success((200, Data(publicStatsJSON.utf8))))

        _ = try await client().loadStats()

        let request = try #require(StatsStub.shared.requests.first)
        #expect(request.timeoutInterval == 8)
        #expect(MidgarPublicStatsClient.resourceTimeout <= 10)
    }

    @Test func theSessionKeepsNothingBetweenRequests() {
        let configuration = MidgarPublicStatsClient.makeSession().configuration

        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(!configuration.waitsForConnectivity)
        #expect(configuration.timeoutIntervalForRequest == 8)
        #expect(configuration.timeoutIntervalForResource == 10)
    }

    @Test func anErrorStatusIsAFailureNotAnEmptyAnswer() async {
        StatsStub.shared.answer(.success((503, Data("{}".utf8))))

        await #expect(throws: MidgarPublicStatsError.status(503)) { try await client().loadStats() }
        #expect(StatsStub.shared.requests.count == 1)
    }

    @Test func aBodyThatIsNotTheStatsIsAFailure() async {
        StatsStub.shared.answer(.success((200, Data("<html>offline portal</html>".utf8))))

        await #expect(throws: (any Error).self) { try await client().loadStats() }
    }

    @Test func noNetworkIsAFailureAndIsNotRetried() async {
        StatsStub.shared.answer(.failure(URLError(.timedOut)))

        await #expect(throws: URLError.self) { try await client().loadStats() }
        #expect(StatsStub.shared.requests.count == 1)
    }
}
