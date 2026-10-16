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
    public let tokenProvider: (@Sendable () async -> String?)?
    public let userAgent: String
    public let timeout: TimeInterval
    public let logger: (@Sendable (String) -> Void)?

    public init(
        baseURL: URL = MidgarHTTPConfiguration.defaultBaseURL,
        appID: String,
        session: URLSession = .shared,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        userAgent: String? = nil,
        timeout: TimeInterval = 30,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.appID = appID
        self.session = session
        self.tokenProvider = tokenProvider
        self.userAgent = userAgent ?? Self.defaultUserAgent()
        self.timeout = timeout
        self.logger = logger
    }

    /// The same configuration with another token provider. Pass nil for a client that must never authorize itself, such as the identity client, whose own calls would otherwise wait on the token they are fetching.
    public func settingTokenProvider(_ tokenProvider: (@Sendable () async -> String?)?) -> MidgarHTTPConfiguration {
        MidgarHTTPConfiguration(
            baseURL: baseURL,
            appID: appID,
            session: session,
            tokenProvider: tokenProvider,
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
