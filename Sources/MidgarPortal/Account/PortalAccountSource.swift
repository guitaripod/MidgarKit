import Foundation
import MidgarCore

/// `GET /v1/identity/me/apps`: the registry slugs of the apps that hold a live session for the caller's Midgar ID.
struct PortalAppsResponse: Decodable, Sendable, Equatable {
    let apps: [String]
}

/// `GET /v1/ledger/entitlements`, reduced to what the portal shows. Dates are Unix milliseconds. The ledger's `kind` is `non_consumable` or `subscription`.
struct PortalEntitlementsResponse: Decodable, Sendable, Equatable {
    let entitlements: [PortalEntitlement]
}

/// One thing the ledger says the person owns in one app.
struct PortalEntitlement: Decodable, Sendable, Equatable {
    let app: String
    let entitlement: String?
    let kind: String
    let expiresDate: Double?
    let graceExpiresDate: Double?
    let inGracePeriod: Bool

    init(
        app: String,
        entitlement: String?,
        kind: String,
        expiresDate: Double? = nil,
        graceExpiresDate: Double? = nil,
        inGracePeriod: Bool = false
    ) {
        self.app = app
        self.entitlement = entitlement
        self.kind = kind
        self.expiresDate = expiresDate
        self.graceExpiresDate = graceExpiresDate
        self.inGracePeriod = inGracePeriod
    }
}

/// Where the portal learns who the person is across Midgar apps. Both calls are read-only and display only: nothing they return grants access in another app.
protocol PortalAccountSource: Sendable {
    func appSlugs() async throws -> [String]
    func entitlements() async throws -> [PortalEntitlement]
}

/// The identity service and the ledger, over the app's authorizing HTTP client. A missing Midgar ID, no network or a refusal throws, and the caller treats every throw as "no account".
struct LivePortalAccountSource: PortalAccountSource {
    let http: MidgarHTTPClient

    func appSlugs() async throws -> [String] {
        let response: PortalAppsResponse = try await http.send(
            MidgarRequest(service: "identity", path: "me/apps", neverRetries: true)
        )
        return response.apps
    }

    func entitlements() async throws -> [PortalEntitlement] {
        let response: PortalEntitlementsResponse = try await http.send(
            MidgarRequest(service: "ledger", path: "entitlements", neverRetries: true)
        )
        return response.entitlements
    }
}
