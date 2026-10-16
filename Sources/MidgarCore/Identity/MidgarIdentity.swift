import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The client side of the Midgar ID (D4, D12): a shared keychain identity that every Midgar app on every device of an Apple Account reads, and a per-app session that is minted, attached, refreshed and recovered as the identity service requires.
///
/// Create one per app, hand ``authorizing(_:)`` the app's HTTP configuration, and build the app's ``MidgarHTTPClient`` from the result so every request carries `Authorization: Bearer`. The identity talks to the service through its own client without a token provider, so its calls never wait on the token they are fetching.
public actor MidgarIdentity {
    static let service = "identity"
    static let refreshMargin: TimeInterval = 60

    let appID: String
    let bundleID: String
    let http: MidgarHTTPClient
    let store: MidgarIdentityStore
    let attestation: any MidgarAttestation
    let clock: @Sendable () -> Date
    let log: MidgarIdentityLogger

    private var cached: LiveSession?
    private var flight: Task<Result<LiveSession, any Error>, Never>?

    /// - Parameters:
    ///   - httpConfiguration: The app's gateway configuration. Its `appID` is the registry slug that names the per-app keychain item. Its token provider is ignored for the identity's own calls.
    ///   - bundleID: The bundle id sent to mint and attach, which the service checks against the registry.
    ///   - accessGroup: The shared item's access group. Pass nil where the app has no such entitlement.
    ///   - keychain: Defaults to ``MidgarSecItemKeychain`` where the Security framework exists and to an in-memory keychain elsewhere.
    ///   - attestation: Defaults to App Attest where DeviceCheck exists and to an unsupported stand-in elsewhere.
    public init(
        httpConfiguration: MidgarHTTPConfiguration,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        accessGroup: String? = MidgarKeychainLayout.defaultAccessGroup,
        keychain: (any MidgarKeychain)? = nil,
        attestation: (any MidgarAttestation)? = nil,
        logger: MidgarIdentityLogger = .standard
    ) {
        self.init(
            appID: httpConfiguration.appID,
            bundleID: bundleID,
            http: MidgarHTTPClient(configuration: httpConfiguration.settingTokenProvider(nil)),
            keychain: keychain ?? Self.platformKeychain(accessGroup: accessGroup),
            attestation: attestation ?? Self.platformAttestation(),
            clock: { Date() },
            log: logger
        )
    }

    init(
        appID: String,
        bundleID: String,
        http: MidgarHTTPClient,
        keychain: any MidgarKeychain,
        attestation: any MidgarAttestation,
        clock: @escaping @Sendable () -> Date,
        log: MidgarIdentityLogger
    ) {
        self.appID = appID
        self.bundleID = bundleID
        self.http = http
        self.store = MidgarIdentityStore(keychain: keychain, appID: appID)
        self.attestation = attestation
        self.clock = clock
        self.log = log
    }

    /// The configuration with this identity as its token provider.
    public nonisolated func authorizing(_ configuration: MidgarHTTPConfiguration) -> MidgarHTTPConfiguration {
        configuration.settingTokenProvider(tokenProvider)
    }

    /// Returns a valid access token, or nil when none can be had right now. Pass it to ``MidgarHTTPConfiguration``.
    public nonisolated var tokenProvider: @Sendable () async -> String? {
        { [self] in try? await accessToken() }
    }

    /// A valid access token, refreshed when it expires within 60 seconds. Callers that arrive while a refresh runs share it, so one expiry makes one request.
    public func accessToken() async throws -> String {
        try await currentSession().accessToken
    }

    /// The resolved Midgar ID, the value for `appAccountToken`. Answered from memory or the per-app keychain item when possible and from the service otherwise.
    public var midgarId: String {
        get async throws {
            if let cached {
                return cached.midgarId
            }
            if let stored = try await normalized({ try store.readSession() }) {
                return stored.midgarId
            }
            return try await currentSession().midgarId
        }
    }

    /// The attestation tier of the current access token.
    public var tier: MidgarIdentityTier {
        get async throws {
            try await currentSession().tier
        }
    }

    /// Forgets the in-memory access token so the next call refreshes. Stored items are untouched.
    func dropCachedSession() {
        cached = nil
    }

    func adopt(_ session: LiveSession) {
        cached = session
    }

    /// Runs the body and rethrows its failure as a ``MidgarIdentityError``.
    func normalized<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch {
            throw MidgarIdentityError.normalizing(error)
        }
    }

    private func currentSession() async throws -> LiveSession {
        if let cached, cached.isFresh(at: clock(), margin: Self.refreshMargin) {
            return cached
        }
        if let flight {
            return try await flight.value.get()
        }
        let started = Task { await self.runFlight() }
        flight = started
        return try await started.value.get()
    }

    /// Runs one session flow and clears the flight in the same actor turn that publishes its result, so a later caller can never see a finished flight.
    private func runFlight() async -> Result<LiveSession, any Error> {
        let result: Result<LiveSession, any Error>
        do {
            let session = try await normalized { try await establishSession() }
            cached = session
            result = .success(session)
        } catch {
            result = .failure(error)
        }
        flight = nil
        return result
    }

    private static func platformKeychain(accessGroup: String?) -> any MidgarKeychain {
        #if canImport(Security)
        return MidgarSecItemKeychain(accessGroup: accessGroup)
        #else
        return MidgarInMemoryKeychain()
        #endif
    }

    private static func platformAttestation() -> any MidgarAttestation {
        #if canImport(DeviceCheck)
        return MidgarAppAttestation()
        #else
        return MidgarUnsupportedAttestation()
        #endif
    }
}
