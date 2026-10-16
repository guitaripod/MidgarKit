import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one HTTP client Midgar apps use to reach `api.midgarcorp.cc`. Requests go to `/v1/<service>/<path>`.
public final class MidgarHTTPClient: Sendable {
    private let configuration: MidgarHTTPConfiguration
    private let retryPolicy: MidgarRetryPolicy
    private let sleep: @Sendable (Duration) async throws -> Void

    public convenience init(configuration: MidgarHTTPConfiguration) {
        self.init(
            configuration: configuration,
            retryPolicy: .standard,
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    init(
        configuration: MidgarHTTPConfiguration,
        retryPolicy: MidgarRetryPolicy,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.configuration = configuration
        self.retryPolicy = retryPolicy
        self.sleep = sleep
    }

    /// Sends the request and decodes a 2xx body as `Response`.
    public func send<Response: Decodable & Sendable>(_ request: MidgarRequest) async throws(MidgarHTTPError) -> Response {
        let (data, _) = try await sendRaw(request)
        return try decode(Response.self, from: data)
    }

    /// Sends the request and returns the 2xx body and response. Non-2xx statuses still throw.
    public func sendRaw(_ request: MidgarRequest) async throws(MidgarHTTPError) -> (Data, HTTPURLResponse) {
        let requestID = UUID().uuidString
        let started = ContinuousClock.now
        do throws(MidgarHTTPError) {
            let (data, response) = try await execute(request, requestID: requestID)
            emitLog(request, requestID: requestID, started: started, status: response.statusCode, outcome: "ok")
            return (data, response)
        } catch {
            emitLog(request, requestID: requestID, started: started, status: error.httpStatus, outcome: error.logName)
            throw error
        }
    }

    /// Runs the attempts for one request. Only retryable requests get more than one attempt.
    private func execute(_ request: MidgarRequest, requestID: String) async throws(MidgarHTTPError) -> (Data, HTTPURLResponse) {
        let urlRequest = try prepare(request, requestID: requestID)
        let maximumAttempts = request.isRetryable ? retryPolicy.maximumAttempts : 1
        var attempt = 1
        while true {
            let authorizedRequest = await authorized(urlRequest)
            let exchange = await transmit(authorizedRequest, preservesUnauthorizedCode: request.preservesUnauthorizedCode)
            switch exchange.result {
            case .success(let pair):
                return pair
            case .failure(let error):
                guard attempt < maximumAttempts,
                      error.isRetryable,
                      let delay = retryPolicy.delay(afterAttempt: attempt, retryAfter: exchange.retryAfter)
                else {
                    throw error
                }
                try await pause(for: delay)
                attempt += 1
            }
        }
    }

    private struct Exchange: Sendable {
        let result: Result<(Data, HTTPURLResponse), MidgarHTTPError>
        let retryAfter: TimeInterval?
    }

    private func transmit(_ urlRequest: URLRequest, preservesUnauthorizedCode: Bool) async -> Exchange {
        do {
            let (data, response) = try await configuration.session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                return Exchange(result: .failure(.server(status: 0, code: nil, message: "HTTP 0")), retryAfter: nil)
            }
            guard (200...299).contains(http.statusCode) else {
                return Exchange(
                    result: .failure(MidgarHTTPError(response: http, data: data, preservesUnauthorizedCode: preservesUnauthorizedCode)),
                    retryAfter: http.midgarRetryAfter
                )
            }
            return Exchange(result: .success((data, http)), retryAfter: nil)
        } catch {
            return Exchange(result: .failure(MidgarHTTPError(transport: error)), retryAfter: nil)
        }
    }

    private func prepare(_ request: MidgarRequest, requestID: String) throws(MidgarHTTPError) -> URLRequest {
        guard let url = request.url(relativeTo: configuration.baseURL) else {
            throw .invalidRequest("The service name or path cannot form a URL.")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = configuration.timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let body = request.body {
            urlRequest.httpBody = try encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(configuration.appID, forHTTPHeaderField: "X-App-ID")
        urlRequest.setValue(requestID, forHTTPHeaderField: "X-Midgar-Request-Id")
        urlRequest.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return urlRequest
    }

    /// Asks the token provider on every attempt, so a token refreshed between retries is used.
    private func authorized(_ urlRequest: URLRequest) async -> URLRequest {
        guard let token = await configuration.tokenProvider?(), !token.isEmpty else {
            return urlRequest
        }
        var request = urlRequest
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func encode(_ body: any Encodable & Sendable) throws(MidgarHTTPError) -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw .invalidRequest("The request body is not valid JSON.")
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws(MidgarHTTPError) -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }

    private func pause(for delay: TimeInterval) async throws(MidgarHTTPError) {
        do {
            try await sleep(.seconds(delay))
        } catch {
            throw .cancelled
        }
    }

    /// One debug line per request: method, service, path, status, outcome, duration and request id. Never headers or bodies.
    private func emitLog(
        _ request: MidgarRequest,
        requestID: String,
        started: ContinuousClock.Instant,
        status: Int?,
        outcome: String
    ) {
        guard let logger = configuration.logger else {
            return
        }
        let elapsed = started.duration(to: .now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        let statusText = status.map { String($0) } ?? "-"
        logger(
            "http \(request.method.rawValue) service=\(request.service) path=\(request.logPath) "
                + "status=\(statusText) outcome=\(outcome) duration=\(milliseconds)ms request=\(requestID)"
        )
    }
}
