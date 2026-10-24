import Foundation
import MidgarCore

/// The mako routes MidgarCredits uses, through the gateway (`/v1/intelligence/v1/...`).
///
/// Authentication has two modes, decided per request. Without a legacy API key the request is Midgar-ID-native: `Authorization: Bearer <access JWT>` alone, which mako resolves to the wallet of the Midgar ID. With one, the request sends both credentials, `Authorization: Bearer <api key>` plus `X-Midgar-Token: <access JWT>`, which is how mako links a user it already knows by key to the Midgar ID's wallet.
///
/// No request is retried inside the HTTP client (`neverRetries`): a 503 carries `Retry-After: 5` and the client would sit through two of them, and the purchase validation has its own retry. A token the service rejects as expired is still replaced once by the client.
struct CreditsAPI: Sendable {
    static let service = "intelligence"
    static let balancePath = "v1/credits/balance"
    static let transactionsPath = "v1/credits/transactions"
    static let validatePath = "v1/credits/purchase/revenuecat/validate"
    static let attributionPath = "v1/attribution"
    static let identityPath = "v1/identity"
    static let midgarTokenHeader = "X-Midgar-Token"
    /// An AdServices token is valid for a short while, so a submission that stalls and then succeeds is worse than a quick failure the next launch retries with a fresh token.
    static let attributionTimeout: TimeInterval = 20

    private let configuration: MidgarHTTPConfiguration
    private let identity: any MidgarCreditsIdentity
    private let legacyAPIKey: (@Sendable () async -> String?)?
    private let nativeClient: MidgarHTTPClient

    init(
        configuration: MidgarHTTPConfiguration,
        identity: any MidgarCreditsIdentity,
        legacyAPIKey: (@Sendable () async -> String?)?
    ) {
        self.configuration = configuration
        self.identity = identity
        self.legacyAPIKey = legacyAPIKey
        self.nativeClient = MidgarHTTPClient(configuration: Self.native(configuration, identity: identity))
    }

    func balance() async throws -> CreditsBalanceWire {
        try await send(path: Self.balancePath, method: .get)
    }

    func transactions(page: Int, perPage: Int) async throws -> CreditsTransactionsWire {
        try await send(
            path: Self.transactionsPath,
            method: .get,
            query: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "per_page", value: String(perPage))]
        )
    }

    func validate(_ body: CreditsValidateBody) async throws -> CreditsValidateWire {
        try await send(path: Self.validatePath, method: .post, body: body)
    }

    /// Posts the AdServices token to `POST /v1/attribution` with the same body `AICredits` sends. mako answers 200 with a status for every outcome of the exchange, so only a bad caller sees an error.
    func submitAttribution(token: String) async throws -> AdAttributionSubmission {
        let wire: CreditsAttributionWire = try await send(
            path: Self.attributionPath,
            method: .post,
            body: CreditsAttributionBody(attributionToken: token),
            timeout: Self.attributionTimeout
        )
        return AdAttributionSubmission(
            status: MidgarAdAttributionStatus(rawValue: wire.status) ?? .pending,
            retryAfter: wire.retryAfterSeconds
        )
    }

    /// Sends `DELETE /v1/identity` with the legacy API key as the only credential, and returns false without any request when the app has no legacy key. 200 and 204 are done, and so are 401 and 404: the identity is already gone. The Midgar token stays off the request on purpose, so a deletion never waits on, fails on or links through the Midgar ID.
    func deleteLegacyIdentity() async throws -> Bool {
        guard let key = await legacyAPIKey?(), !key.isEmpty else {
            return false
        }
        let client = MidgarHTTPClient(configuration: configuration.settingTokenProvider({ key }))
        let request = MidgarRequest(service: Self.service, path: Self.identityPath, method: .delete, neverRetries: true)
        do {
            _ = try await client.sendRaw(request)
        } catch .unauthorized, .notFound {
            return true
        } catch {
            throw await translated(error, resolvesBalance: false)
        }
        return true
    }

    private func send<Response: Decodable & Sendable>(
        path: String,
        method: MidgarHTTPMethod,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        resolvesBalance: Bool = true,
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        let route = try await route(timeout: timeout)
        let request = MidgarRequest(
            service: Self.service,
            path: path,
            method: method,
            query: query,
            headers: route.headers,
            body: body,
            neverRetries: true
        )
        do {
            return try await route.client.send(request)
        } catch {
            throw await translated(error, resolvesBalance: resolvesBalance)
        }
    }

    /// The client and headers for one request: native, or legacy with the Midgar token beside the key. A failing token provider in legacy mode fails the request instead of sending the key alone, because mako would then answer from the old per-app balance and the app would show a number the wallet does not hold.
    private func route(timeout: TimeInterval?) async throws -> (client: MidgarHTTPClient, headers: [String: String]) {
        let base = timeout.map { configuration.settingTimeout($0) } ?? configuration
        guard let key = await legacyAPIKey?(), !key.isEmpty else {
            return (timeout == nil ? nativeClient : MidgarHTTPClient(configuration: Self.native(base, identity: identity)), [:])
        }
        let token: String
        do {
            token = try await identity.accessToken()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MidgarCreditsError.identityUnavailable
        }
        let client = MidgarHTTPClient(configuration: base.settingTokenProvider({ key }))
        return (client, [Self.midgarTokenHeader: token])
    }

    private static func native(_ configuration: MidgarHTTPConfiguration, identity: any MidgarCreditsIdentity) -> MidgarHTTPConfiguration {
        configuration.settingTokenProvider(
            { try await identity.accessToken() },
            invalidator: { _ in await identity.invalidateAccessToken() }
        )
    }

    /// Maps a gateway failure. A 402 gets the wallet balance read afterwards, because the envelope's message that holds it as text does not survive ``MidgarHTTPError``.
    func translated(_ error: any Error, resolvesBalance: Bool = true) async -> any Error {
        guard let http = error as? MidgarHTTPError else {
            return error
        }
        let mapped = MidgarCreditsError.mapping(http)
        guard resolvesBalance, case MidgarCreditsError.insufficientCredits = mapped else {
            return mapped
        }
        let balance: CreditsBalanceWire? = try? await send(path: Self.balancePath, method: .get, resolvesBalance: false)
        return MidgarCreditsError.insufficientCredits(balance: balance?.balance)
    }
}

extension MidgarHTTPConfiguration {
    /// The same configuration with another request timeout.
    fileprivate func settingTimeout(_ timeout: TimeInterval) -> MidgarHTTPConfiguration {
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
}
