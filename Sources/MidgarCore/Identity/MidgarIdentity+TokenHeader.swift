import Foundation

extension MidgarIdentity {
    /// The header mako reads the Midgar ID's access token from, next to the legacy api key in `Authorization`.
    public static let midgarTokenHeaderName = "X-Midgar-Token"

    /// The `X-Midgar-Token` header carrying the current access token, or nil when the identity cannot answer within `timeout`, fails, or has an empty token. It never throws and never waits longer than `timeout`, so a call it decorates is never slower than `timeout` for the sake of a token it can do without.
    public func midgarTokenHeader(within timeout: Duration) async -> (name: String, value: String)? {
        await Self.tokenHeader(within: timeout) { try await self.accessToken() }
    }

    static func tokenHeader(
        within timeout: Duration,
        token: @escaping @Sendable () async throws -> String
    ) async -> (name: String, value: String)? {
        guard let value = try? await AsyncTimeout.run(for: timeout, operation: token), !value.isEmpty else { return nil }
        return (midgarTokenHeaderName, value)
    }
}
