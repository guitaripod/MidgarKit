import Foundation

/// The HTTP verbs the gateway routes use.
public enum MidgarHTTPMethod: String, Sendable, Hashable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Methods that may be retried without asking the caller, per RFC 9110.
    var isIdempotentByDefinition: Bool {
        switch self {
        case .get, .head, .put, .delete:
            return true
        case .post, .patch:
            return false
        }
    }
}

/// One call to a gateway service. The client sends it to `/v1/<service>/<path>`.
public struct MidgarRequest: Sendable {
    public let service: String
    public let path: String
    public let method: MidgarHTTPMethod
    public let query: [URLQueryItem]
    public let headers: [String: String]
    public let body: (any Encodable & Sendable)?
    public let idempotent: Bool
    public let preservesUnauthorizedCode: Bool

    /// - Parameters:
    ///   - service: The gateway service name, such as `catalog`. Use `health` for `/v1/health`.
    ///   - path: The path after the service, such as `apps/42`. Empty for the service root.
    ///   - body: Encoded as JSON with `Content-Type: application/json`.
    ///   - idempotent: Opts a non-idempotent method (POST, PATCH) into retries. GET, HEAD, PUT and DELETE always retry.
    ///   - preservesUnauthorizedCode: Reports a 401 as ``MidgarHTTPError/server(status:code:message:)`` with the envelope's code instead of ``MidgarHTTPError/unauthorized``, for callers such as the identity flows that act on the code.
    public init(
        service: String,
        path: String = "",
        method: MidgarHTTPMethod = .get,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        idempotent: Bool = false,
        preservesUnauthorizedCode: Bool = false
    ) {
        self.service = service
        self.path = path
        self.method = method
        self.query = query
        self.headers = headers
        self.body = body
        self.idempotent = idempotent
        self.preservesUnauthorizedCode = preservesUnauthorizedCode
    }

    var isRetryable: Bool {
        method.isIdempotentByDefinition || idempotent
    }

    /// The path segments without empty pieces, so `/apps//42/` and `apps/42` name the same resource.
    private var pathSegments: [Substring] {
        path.split(separator: "/", omittingEmptySubsequences: true)
    }

    /// The path as it appears in logs: `/apps/42`, or `/` for the service root.
    var logPath: String {
        pathSegments.isEmpty ? "/" : "/" + pathSegments.joined(separator: "/")
    }

    /// Builds `<base>/v1/<service>/<path>?<query>`, percent-encoding the service and every path segment.
    func url(relativeTo base: URL) -> URL? {
        guard !service.isEmpty, !service.contains("/"),
              let encodedService = service.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        let encodedSegments = pathSegments.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
        components.percentEncodedPath = Self.trimmingTrailingSlashes(components.percentEncodedPath)
            + "/v1/" + encodedService
            + (encodedSegments.isEmpty ? "" : "/" + encodedSegments.joined(separator: "/"))
        components.queryItems = query.isEmpty ? nil : query
        return components.url
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
