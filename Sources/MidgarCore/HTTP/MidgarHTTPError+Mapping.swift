import Foundation

extension MidgarHTTPError {
    /// Maps a failure that happened before any HTTP status arrived.
    init(transport error: any Error) {
        if error is CancellationError {
            self = .cancelled
            return
        }
        guard let urlError = error as? URLError else {
            self = .offline
            return
        }
        switch urlError.code {
        case .cancelled:
            self = .cancelled
        case .timedOut:
            self = .timeout
        default:
            self = .offline
        }
    }

    /// Maps a non-2xx response. Reads the `{"error":{"code","message"}}` envelope and mako's legacy shapes.
    init(response: HTTPURLResponse, data: Data) {
        switch response.statusCode {
        case 401:
            self = .unauthorized
        case 402:
            self = .paymentRequired
        case 404:
            self = .notFound
        case 429:
            self = .rateLimited(retryAfter: response.midgarRetryAfter)
        default:
            let details = Self.envelopeDetails(in: data)
            self = .server(
                status: response.statusCode,
                code: details.code,
                message: details.message ?? "HTTP \(response.statusCode)"
            )
        }
    }

    var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .rateLimited:
            return true
        case .server(let status, _, _):
            return [502, 503, 504].contains(status)
        case .unauthorized, .paymentRequired, .notFound, .decoding, .invalidRequest, .cancelled:
            return false
        }
    }

    /// The HTTP status this error stands for, or nil when no response arrived.
    var httpStatus: Int? {
        switch self {
        case .unauthorized:
            return 401
        case .paymentRequired:
            return 402
        case .notFound:
            return 404
        case .rateLimited:
            return 429
        case .server(let status, _, _):
            return status
        case .offline, .timeout, .decoding, .invalidRequest, .cancelled:
            return nil
        }
    }

    /// A short case name for the debug log. Never includes associated values, which can carry server text.
    var logName: String {
        switch self {
        case .offline: return "offline"
        case .timeout: return "timeout"
        case .unauthorized: return "unauthorized"
        case .paymentRequired: return "paymentRequired"
        case .rateLimited: return "rateLimited"
        case .notFound: return "notFound"
        case .server: return "server"
        case .decoding: return "decoding"
        case .invalidRequest: return "invalidRequest"
        case .cancelled: return "cancelled"
        }
    }

    /// Reads `error.code` and `error.message` from the envelope, or the string forms of `error` and `message`.
    private static func envelopeDetails(in data: Data) -> (code: String?, message: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        let nested = object["error"] as? [String: Any]
        let code = (nested?["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let candidates: [String?] = [
            nested?["message"] as? String,
            object["error"] as? String,
            object["message"] as? String,
        ]
        let message = candidates.compactMap { $0 }.first { !$0.isEmpty }
        return (code, message)
    }
}
