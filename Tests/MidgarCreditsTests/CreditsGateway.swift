import Foundation
import MidgarCore

struct CreditsReply: Sendable {
    let status: Int
    let body: Data
    let failure: URLError.Code?

    static func json(_ status: Int, _ text: String) -> CreditsReply {
        CreditsReply(status: status, body: Data(text.utf8), failure: nil)
    }

    static func failing(_ code: URLError.Code) -> CreditsReply {
        CreditsReply(status: 0, body: Data(), failure: code)
    }

    static func balance(_ credits: Int) -> CreditsReply {
        .json(200, #"{"balance":\#(credits),"currency":"credits"}"#)
    }

    static func credited(added: Int, newBalance: Int) -> CreditsReply {
        .json(200, #"{"success":true,"purchase_id":"p-1","credits_added":\#(added),"new_balance":\#(newBalance)}"#)
    }

    static func refused(_ status: Int, _ code: String, _ message: String) -> CreditsReply {
        .json(status, #"{"error":{"message":"\#(message)","type":"x","param":null,"code":"\#(code)"}}"#)
    }

    static let creditedShortly = refused(500, "internal_error", "An internal error occurred. Please try again later.")
    static let walletUnavailable = refused(503, "wallet_unavailable", "Your credit balance is temporarily unavailable.")
    static let notVerified = refused(400, "bad_request", "Purchase could not be verified with RevenueCat")
    static let alreadyProcessed = refused(400, "bad_request", "Purchase has already been processed")

    static let creditPending = refused(409, "credit_pending", "Could not verify the purchase right now; it will be credited shortly.")
    static let unverifiable = refused(400, "unverifiable_purchase", "Purchase could not be verified with RevenueCat")
    static let processed = refused(400, "already_processed", "Purchase has already been processed")
}

struct CreditsCapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    var path: String { url.path }

    var json: [String: Any] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return [:]
        }
        return object
    }
}

final class CreditsStubProtocol: URLProtocol {
    static let hostSuffix = ".credits-stub.test"

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
        let captured = CreditsCapturedRequest(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        let reply = CreditsGateway.gateways.reply(for: host, to: captured)
        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
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

/// A scripted mako behind the gateway. Each route answers from a queue; the last reply repeats once the queue is down to one. The request log and the queues are touched only inside `lock`.
final class CreditsGateway: @unchecked Sendable {
    /// Routes by host to the handler a gateway installed. The lock guards the handler table, which is what makes the unchecked conformance sound.
    final class Table: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: @Sendable (CreditsCapturedRequest) -> CreditsReply] = [:]

        func install(_ handler: @escaping @Sendable (CreditsCapturedRequest) -> CreditsReply, for host: String) {
            lock.withLock { handlers[host] = handler }
        }

        func reply(for host: String, to request: CreditsCapturedRequest) -> CreditsReply {
            let handler = lock.withLock { handlers[host] }
            return handler?(request) ?? .json(599, "{}")
        }
    }

    static let gateways = Table()

    let host = UUID().uuidString.lowercased() + CreditsStubProtocol.hostSuffix
    private let lock = NSLock()
    private var queues: [String: [CreditsReply]] = [:]
    private var log: [CreditsCapturedRequest] = []

    init() {
        Self.gateways.install({ [self] request in answer(request) }, for: host)
    }

    var baseURL: URL { URL(string: "https://\(host)")! }
    var requests: [CreditsCapturedRequest] { lock.withLock { log } }

    func requests(to suffix: String) -> [CreditsCapturedRequest] {
        requests.filter { $0.path.hasSuffix(suffix) }
    }

    func script(_ suffix: String, _ replies: CreditsReply...) {
        lock.withLock { queues[suffix] = replies }
    }

    private func answer(_ request: CreditsCapturedRequest) -> CreditsReply {
        lock.withLock {
            log.append(request)
            guard let key = queues.keys.first(where: { request.path.hasSuffix($0) }), var queue = queues[key] else {
                return .json(404, "{}")
            }
            let reply = queue.count > 1 ? queue.removeFirst() : queue[0]
            queues[key] = queue
            return reply
        }
    }

    func configuration(appID: String = "app-test") -> MidgarHTTPConfiguration {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [CreditsStubProtocol.self]
        return MidgarHTTPConfiguration(
            baseURL: baseURL,
            appID: appID,
            session: URLSession(configuration: sessionConfiguration),
            userAgent: "CreditsTests/1.0",
            timeout: 5
        )
    }
}

extension CreditsReply {
    static func attribution(_ status: String, retryAfter: Int? = nil) -> CreditsReply {
        let retry = retryAfter.map { #","retry_after_seconds":\#($0)"# } ?? ""
        return .json(200, #"{"status":"\#(status)","attributed":\#(status == "attributed")\#(retry)}"#)
    }
}
