import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MidgarCore
import MidgarIntelligence

actor CallCounter {
    private(set) var count = 0

    func bump() {
        count += 1
    }
}

struct FakeFailure: Error, Equatable {}

/// A scripted model. `deltas` stream first, then `failure` (if any) ends the stream; `answer` is the full text of `respond`.
struct FakeModel: MidgarOnDeviceLanguageModel {
    var availability: MidgarOnDeviceAvailability = .available
    var route: MidgarRoute = .onDevice
    var answer = "answer"
    var deltas: [String] = ["ans", "wer"]
    var failure: (any Error & Sendable)?
    var failsBeforeDeltas = true
    let respondCalls = CallCounter()
    let streamCalls = CallCounter()

    func respond(to prompt: MidgarPrompt) async throws -> MidgarCompletion {
        await respondCalls.bump()
        if let failure {
            throw failure
        }
        return MidgarCompletion(text: answer, route: route, creditsCharged: route == .cloud ? 3 : nil)
    }

    func streamResponse(to prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error> {
        let deltas = deltas
        let failure = failure
        let failsBeforeDeltas = failsBeforeDeltas
        let calls = streamCalls
        return AsyncThrowingStream { continuation in
            Task {
                await calls.bump()
                if let failure, failsBeforeDeltas {
                    continuation.finish(throwing: failure)
                    return
                }
                for delta in deltas {
                    continuation.yield(delta)
                }
                continuation.finish(throwing: failure)
            }
        }
    }
}

func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
    var result: [String] = []
    for try await delta in stream {
        result.append(delta)
    }
    return result
}

func killConfig(_ names: String...) throws -> MidgarConfig {
    let kill = names.map { "\"\($0)\":true" }.joined(separator: ",")
    let json = "{\"app\":\"app-test\",\"version\":1,\"kill\":{\(kill)}}"
    let document = try JSONDecoder().decode(MidgarConfigDocument.self, from: Data(json.utf8))
    return MidgarConfig(document: document, defaults: [:])
}

final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var logger: MidgarIntelligenceLogger {
        { [self] line in lock.withLock { stored.append(line) } }
    }

    var lines: [String] {
        lock.withLock { stored }
    }
}

struct StubReply: Sendable {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json(_ status: Int, _ text: String, headers: [String: String] = [:]) -> StubReply {
        StubReply(status: status, headers: headers, body: Data(text.utf8))
    }
}

struct CapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
}

final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    private let lock = NSLock()
    private var replies: [String: [StubReply]] = [:]
    private var captured: [String: [CapturedRequest]] = [:]

    func enqueue(_ queue: [StubReply], for host: String) {
        lock.withLock { replies[host, default: []].append(contentsOf: queue) }
    }

    func next(for host: String, request: CapturedRequest) -> StubReply {
        lock.withLock {
            captured[host, default: []].append(request)
            guard let queue = replies[host], !queue.isEmpty else {
                return .json(599, "{}")
            }
            replies[host] = Array(queue.dropFirst())
            return queue[0]
        }
    }

    func requests(for host: String) -> [CapturedRequest] {
        lock.withLock { captured[host, default: []] }
    }
}

final class StubURLProtocol: URLProtocol {
    static let hostSuffix = ".intelligence-stub.test"

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
        let reply = StubRegistry.shared.next(for: host, request: captured)
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
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

struct CloudTestHost: Sendable {
    let host = UUID().uuidString.lowercased() + StubURLProtocol.hostSuffix

    var baseURL: URL {
        URL(string: "https://\(host)")!
    }

    func enqueue(_ replies: [StubReply]) {
        StubRegistry.shared.enqueue(replies, for: host)
    }

    var requests: [CapturedRequest] {
        StubRegistry.shared.requests(for: host)
    }

    func client(logger: (@Sendable (String) -> Void)? = nil) -> MidgarHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return MidgarHTTPClient(
            configuration: MidgarHTTPConfiguration(
                baseURL: baseURL,
                appID: "app-test",
                session: URLSession(configuration: configuration),
                tokenProvider: { "token-abc" },
                userAgent: "TestApp/1.0 MidgarKit/4.0.0",
                timeout: 5,
                logger: logger
            )
        )
    }
}

final class ConfigHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = MidgarConfig()

    var value: MidgarConfig {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
