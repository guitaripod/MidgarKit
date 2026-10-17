import Foundation
import MidgarCore

/// The three mako routes MidgarCredits uses, through the gateway (`/v1/intelligence/v1/...`).
///
/// Authentication has two modes, decided per request. Without a legacy API key the request is Midgar-ID-native: `Authorization: Bearer <access JWT>` alone, which mako resolves to the wallet of the Midgar ID. With one, the request sends both credentials, `Authorization: Bearer <api key>` plus `X-Midgar-Token: <access JWT>`, which is how mako links a user it already knows by key to the Midgar ID's wallet.
///
/// No request is retried inside the HTTP client (`neverRetries`): a 503 carries `Retry-After: 5` and the client would sit through two of them, and the purchase validation has its own retry. A token the service rejects as expired is still replaced once by the client.
struct CreditsAPI: Sendable {
    static let service = "intelligence"
    static let balancePath = "v1/credits/balance"
    static let transactionsPath = "v1/credits/transactions"
    static let validatePath = "v1/credits/purchase/revenuecat/validate"
    static let midgarTokenHeader = "X-Midgar-Token"

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
        self.nativeClient = MidgarHTTPClient(configuration: configuration.settingTokenProvider(
            { try await identity.accessToken() },
            invalidator: { _ in await identity.invalidateAccessToken() }
        ))
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

    private func send<Response: Decodable & Sendable>(
        path: String,
        method: MidgarHTTPMethod,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        resolvesBalance: Bool = true
    ) async throws -> Response {
        let route = try await route()
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
    private func route() async throws -> (client: MidgarHTTPClient, headers: [String: String]) {
        guard let key = await legacyAPIKey?(), !key.isEmpty else {
            return (nativeClient, [:])
        }
        let token: String
        do {
            token = try await identity.accessToken()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MidgarCreditsError.identityUnavailable
        }
        let client = MidgarHTTPClient(configuration: configuration.settingTokenProvider({ key }))
        return (client, [Self.midgarTokenHeader: token])
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
