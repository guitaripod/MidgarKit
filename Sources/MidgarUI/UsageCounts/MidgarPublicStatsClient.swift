import Foundation

/// Where an app's Usage Counts screen gets Midgar's public numbers. Tests replace it.
protocol MidgarPublicStatsLoading: Sendable {
    func loadStats() async throws -> MidgarPublicStats
}

/// Why the public numbers could not be read.
enum MidgarPublicStatsError: Error, Equatable {
    case notHTTP
    case status(Int)
}

/// Reads `GET https://api.midgarcorp.cc/v1/ops/public/stats`, the one public answer that needs no secret and no app id. The request goes straight to that URL on a session that keeps no cookies, credentials or disk cache, carries no header of its own, and is tried once: it gives up after eight seconds and the screen then leaves the numbers out.
struct MidgarPublicStatsClient: MidgarPublicStatsLoading {
    static let url = URL(string: "https://api.midgarcorp.cc/v1/ops/public/stats")!
    static let requestTimeout: TimeInterval = 8
    static let resourceTimeout: TimeInterval = 10

    private let session: URLSession

    init(session: URLSession = MidgarPublicStatsClient.makeSession()) {
        self.session = session
    }

    func loadStats() async throws -> MidgarPublicStats {
        var request = URLRequest(url: Self.url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.requestTimeout)
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MidgarPublicStatsError.notHTTP
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MidgarPublicStatsError.status(http.statusCode)
        }
        return try JSONDecoder().decode(MidgarPublicStats.self, from: data)
    }

    /// A session that remembers nothing between launches and does not wait for connectivity.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: configuration)
    }
}
