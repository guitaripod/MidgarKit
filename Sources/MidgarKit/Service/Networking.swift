import Foundation

extension URLSession {
    /// Shared session for Midgar with bounded timeouts and a dedicated on-disk cache so the
    /// catalog and artwork survive cold launches without polluting the host app's URLCache.
    static let midgar: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("MidgarURLCache")
        )
        return URLSession(configuration: config)
    }()
}

struct ITunesClient {
    var session: URLSession = .midgar

    /// Batch-looks up apps by track id in a single request, scoped to a storefront. Returns a map
    /// keyed by string track id. Any failure yields an empty map so enrichment degrades silently.
    func lookup(ids: [String], storefront: String?) async -> [String: ITunesApp] {
        guard !ids.isEmpty else { return [:] }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        var query = [
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "200"),
        ]
        if let storefront, !storefront.isEmpty {
            query.append(URLQueryItem(name: "country", value: storefront))
        }
        components.queryItems = query
        guard let url = components.url else { return [:] }

        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
            let decoded = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
            return Dictionary(
                decoded.results.map { (String($0.trackId), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            return [:]
        }
    }
}
