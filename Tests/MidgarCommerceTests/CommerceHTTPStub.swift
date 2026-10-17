import Foundation
import MidgarCore

struct StubReply: Sendable {
    let status: Int
    let body: Data
    let failure: URLError.Code?

    static func json(_ status: Int, _ text: String) -> StubReply {
        StubReply(status: status, body: Data(text.utf8), failure: nil)
    }

    static func failing(_ code: URLError.Code) -> StubReply {
        StubReply(status: 0, body: Data(), failure: code)
    }

    static let accepted = StubReply.json(200, #"{"ok":true}"#)
    static let unreachable = StubReply.failing(.notConnectedToInternet)

    static func refused(_ status: Int, _ code: String) -> StubReply {
        .json(status, #"{"error":{"code":"\#(code)","message":"m"}}"#)
    }
}

struct CapturedRequest: Sendable {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?
}

/// Routes by host to a handler the test owns. The lock guards the handler table, which is what makes the unchecked conformance sound.
final class StubRoutes: @unchecked Sendable {
    static let shared = StubRoutes()

    private let lock = NSLock()
    private var handlers: [String: @Sendable (CapturedRequest) -> StubReply] = [:]

    func install(_ handler: @escaping @Sendable (CapturedRequest) -> StubReply, for host: String) {
        lock.withLock { handlers[host] = handler }
    }

    func reply(for host: String, to request: CapturedRequest) -> StubReply {
        let handler = lock.withLock { handlers[host] }
        return handler?(request) ?? .json(599, "{}")
    }
}

final class CommerceStubProtocol: URLProtocol {
    static let hostSuffix = ".commerce-stub.test"

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
        let reply = StubRoutes.shared.reply(for: host, to: captured)
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

/// A scripted ledger: the test sets what each route answers and reads what arrived. All fields are touched only inside `lock`.
final class FakeLedger: @unchecked Sendable {
    let host = UUID().uuidString.lowercased() + CommerceStubProtocol.hostSuffix
    private let lock = NSLock()
    private var reportReply: StubReply = .accepted
    private var entitlementsReply: StubReply = .unreachable
    private var reported: [String] = []
    private var queries: [String?] = []
    private var authorizationHeaders: [String] = []

    init() {
        StubRoutes.shared.install({ [self] request in answer(request) }, for: host)
    }

    var baseURL: URL { URL(string: "https://\(host)")! }
    var reports: [String] { lock.withLock { reported } }
    var entitlementQueries: [String?] { lock.withLock { queries } }
    var authorizations: [String] { lock.withLock { authorizationHeaders } }

    func setReportReply(_ reply: StubReply) { lock.withLock { reportReply = reply } }
    func setEntitlementsReply(_ reply: StubReply) { lock.withLock { entitlementsReply = reply } }

    func serve(midgarId: String, environment: String = "Production", _ entries: [String] = []) {
        setEntitlementsReply(.json(200, #"{"midgarId":"\#(midgarId)","environment":"\#(environment)","serverTime":1800000000000,"entitlements":[\#(entries.joined(separator: ","))]}"#))
    }

    static func entry(
        app: String = "app-test",
        entitlement: String?,
        productId: String,
        kind: String,
        expires: Date? = nil,
        grace: Date? = nil,
        inGrace: Bool = false,
        ownership: String = "PURCHASED"
    ) -> String {
        let name = entitlement.map { "\"\($0)\"" } ?? "null"
        let expiresText = expires.map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "null"
        let graceText = grace.map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "null"
        return #"{"app":"\#(app)","entitlement":\#(name),"productId":"\#(productId)","kind":"\#(kind)","originalTransactionId":"1","expiresDate":\#(expiresText),"graceExpiresDate":\#(graceText),"inGracePeriod":\#(inGrace),"ownership":"\#(ownership)"}"#
    }

    private func answer(_ request: CapturedRequest) -> StubReply {
        lock.withLock {
            authorizationHeaders.append(request.headers["Authorization"] ?? "")
            if request.method == "POST", request.url.path == "/v1/ledger/transactions" {
                if let body = request.body,
                   let object = try? JSONSerialization.jsonObject(with: body) as? [String: String],
                   let jws = object["signedTransaction"] {
                    reported.append(jws)
                }
                return reportReply
            }
            if request.method == "GET", request.url.path == "/v1/ledger/entitlements" {
                queries.append(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
                return entitlementsReply
            }
            return .json(404, "{}")
        }
    }
}

func makeStubClient(_ ledger: FakeLedger, tokenProvider: (@Sendable () async throws -> String?)? = nil) -> MidgarHTTPClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CommerceStubProtocol.self]
    return MidgarHTTPClient(configuration: MidgarHTTPConfiguration(
        baseURL: ledger.baseURL,
        appID: "app-test",
        session: URLSession(configuration: configuration),
        tokenProvider: tokenProvider,
        userAgent: "CommerceTests/1.0",
        timeout: 5
    ))
}
