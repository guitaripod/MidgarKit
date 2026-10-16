import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MidgarCore

struct StubReply: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data
    let failure: URLError.Code?

    static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> StubReply {
        StubReply(status: status, headers: headers, body: Data(text.utf8), failure: nil)
    }

    static func failing(_ code: URLError.Code) -> StubReply {
        StubReply(status: 0, headers: [:], body: Data(), failure: code)
    }
}

struct CapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
}

/// The handler table shared by URLProtocol callbacks. Those callbacks are synchronous, so an actor cannot
/// serve them, and the NSLock guards every mutable field, which is what makes the unchecked conformance sound.
final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    private let lock = NSLock()
    private var replies: [String: [StubReply]] = [:]
    private var captured: [String: [CapturedRequest]] = [:]

    func enqueue(_ queue: [StubReply], for host: String) {
        lock.withLock { replies[host, default: []].append(contentsOf: queue) }
    }

    func nextReply(for host: String, request: CapturedRequest) -> StubReply {
        lock.withLock {
            captured[host, default: []].append(request)
            guard let next = replies[host], !next.isEmpty else {
                return .json(599, "{\"error\":\"unexpected request\"}")
            }
            replies[host] = Array(next.dropFirst())
            return next[0]
        }
    }

    func requests(for host: String) -> [CapturedRequest] {
        lock.withLock { captured[host, default: []] }
    }
}

final class StubURLProtocol: URLProtocol {
    static let hostSuffix = ".midgar-stub.test"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(hostSuffix) ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let captured = CapturedRequest(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let reply = StubRegistry.shared.nextReply(for: host, request: captured)
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// One fresh host per test, so parallel tests never share a reply queue.
struct HTTPTestHost: Sendable {
    let host: String
    let baseURL: URL

    init() {
        host = UUID().uuidString.lowercased() + StubURLProtocol.hostSuffix
        baseURL = URL(string: "https://\(host)")!
    }

    func enqueue(_ replies: [StubReply]) {
        StubRegistry.shared.enqueue(replies, for: host)
    }

    var requests: [CapturedRequest] {
        StubRegistry.shared.requests(for: host)
    }
}

extension MidgarRetryPolicy {
    static let testing = MidgarRetryPolicy(
        maximumAttempts: 3,
        baseDelay: 0,
        maximumDelay: 0,
        maximumRetryAfter: 60
    )
}

actor SleepRecorder {
    private(set) var durations: [TimeInterval] = []

    func record(_ duration: Duration) {
        durations.append(duration.timeInterval)
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

func makeStubClient(
    _ host: HTTPTestHost,
    tokenProvider: (@Sendable () async -> String?)? = nil,
    userAgent: String? = "TestApp/1.0 MidgarKit/4.0.0",
    logger: (@Sendable (String) -> Void)? = nil,
    sleeps: SleepRecorder = SleepRecorder()
) -> MidgarHTTPClient {
    let configuration = MidgarHTTPConfiguration(
        baseURL: host.baseURL,
        appID: "app-test",
        session: makeStubSession(),
        tokenProvider: tokenProvider,
        userAgent: userAgent,
        timeout: 5,
        logger: logger
    )
    return MidgarHTTPClient(configuration: configuration, retryPolicy: .testing) { duration in
        await sleeps.record(duration)
    }
}

/// The error an operation throws, or nil when it succeeds.
func thrownError<Value>(_ operation: () async throws -> Value) async -> MidgarHTTPError? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return error as? MidgarHTTPError
    }
}
