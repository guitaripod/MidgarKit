import Foundation
import MidgarCore

/// The body of `POST /v1/ledger/transactions`.
struct LedgerReportBody: Encodable, Sendable {
    let signedTransaction: String
}

/// `GET /v1/ledger/entitlements`. Dates are Unix milliseconds.
struct LedgerEntitlementsResponse: Codable, Sendable, Equatable {
    let midgarId: String
    let environment: String
    let serverTime: Double
    let entitlements: [LedgerEntitlement]
}

struct LedgerEntitlement: Codable, Sendable, Equatable {
    let app: String
    let entitlement: String?
    let productId: String
    let kind: String
    let originalTransactionId: String
    let expiresDate: Double?
    let graceExpiresDate: Double?
    let inGracePeriod: Bool
    let ownership: String?
}

/// The ledger calls, over the app's authorizing HTTP client. Neither call retries inside the client: the store has its own queue and fallbacks.
struct LedgerClient: Sendable {
    let http: MidgarHTTPClient

    func report(signedTransaction: String) async throws(MidgarHTTPError) {
        _ = try await http.sendRaw(MidgarRequest(
            service: "ledger",
            path: "transactions",
            method: .post,
            body: LedgerReportBody(signedTransaction: signedTransaction),
            neverRetries: true
        ))
    }

    func entitlements(sandbox: Bool) async throws(MidgarHTTPError) -> LedgerEntitlementsResponse {
        try await http.send(MidgarRequest(
            service: "ledger",
            path: "entitlements",
            query: sandbox ? [URLQueryItem(name: "environment", value: "Sandbox")] : [],
            neverRetries: true
        ))
    }
}
