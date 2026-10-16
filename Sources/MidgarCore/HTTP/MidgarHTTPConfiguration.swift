import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything `MidgarHTTPClient` needs to reach the Midgar gateway for one app.
public struct MidgarHTTPConfiguration: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.midgarcorp.cc")!

    public let baseURL: URL
    public let appID: String
    public let session: URLSession
    public let tokenProvider: (@Sendable () async throws -> String?)?
    public let tokenInvalidator: (@Sendable (_ rejectedToken: String) async -> Void)?
    public let userAgent: String
    public let timeout: TimeInterval
    public let logger: (@Sendable (String) -> Void)?

    public init(
        baseURL: URL = MidgarHTTPConfiguration.defaultBaseURL,
        appID: String,
        session: URLSession = .shared,
        tokenProvider: (@Sendable () async throws -> String?)? = nil,
        tokenInvalidator: (@Sendable (_ rejectedToken: String) async -> Void)? = nil,
        userAgent: String? = nil,
        timeout: TimeInterval = 30,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.appID = appID
        self.session = session
        self.tokenProvider = tokenProvider
        self.tokenInvalidator = tokenInvalidator
        self.userAgent = userAgent ?? Self.defaultUserAgent()
        self.timeout = timeout
        self.logger = logger
    }

    /// The same configuration with another token provider and the closure that discards a token the service rejected. Pass nil for a client that must never authorize itself, such as the identity client, whose own calls would otherwise wait on the token they are fetching.
    public func settingTokenProvider(
        _ tokenProvider: (@Sendable () async throws -> String?)?,
        invalidator tokenInvalidator: (@Sendable (_ rejectedToken: String) async -> Void)? = nil
    ) -> MidgarHTTPConfiguration {
        MidgarHTTPConfiguration(
            baseURL: baseURL,
            appID: appID,
            session: session,
            tokenProvider: tokenProvider,
            tokenInvalidator: tokenInvalidator,
            userAgent: userAgent,
            timeout: timeout,
            logger: logger
        )
    }

    /// `<app>/<version> MidgarKit/<version>`, read from the host app's bundle.
    private static func defaultUserAgent(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let name = info?["CFBundleName"] as? String ?? "App"
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        return "\(name)/\(version) MidgarKit/\(MidgarKitVersion.current)"
    }
}
