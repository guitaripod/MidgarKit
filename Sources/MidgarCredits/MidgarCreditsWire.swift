import Foundation

struct CreditsBalanceWire: Decodable, Sendable {
    let balance: Int
}

struct CreditsTransactionWire: Decodable, Sendable {
    let id: String
    let type: String
    let amount: Int
    let balanceAfter: Int
    let description: String
    let referenceID: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case amount
        case balanceAfter = "balance_after"
        case description
        case referenceID = "reference_id"
        case createdAt = "created_at"
    }
}

struct CreditsTransactionsWire: Decodable, Sendable {
    let transactions: [CreditsTransactionWire]
    let total: Int
    let page: Int?
    let perPage: Int?

    enum CodingKeys: String, CodingKey {
        case transactions
        case total
        case page
        case perPage = "per_page"
    }
}

/// The body of mako's `POST /v1/credits/purchase/revenuecat/validate`. mako identifies the purchase by `purchase_token`, the App Store transaction id (RevenueCat's `store_purchase_identifier`), and binds the price to the credits through `pack_id` and `product_id`. `platform` is `ios` on every Apple platform: mako only knows `ios` and `android`. `signed_transaction` is not read by mako today; it rides along so the server can verify the JWS itself once RevenueCat is retired.
struct CreditsValidateBody: Encodable, Sendable {
    let packID: String
    let purchaseToken: String
    let productID: String
    let platform: String
    let signedTransaction: String

    enum CodingKeys: String, CodingKey {
        case packID = "pack_id"
        case purchaseToken = "purchase_token"
        case productID = "product_id"
        case platform
        case signedTransaction = "signed_transaction"
    }
}

struct CreditsValidateWire: Decodable, Sendable {
    let success: Bool
    let purchaseID: String
    let creditsAdded: Int
    let newBalance: Int

    enum CodingKeys: String, CodingKey {
        case success
        case purchaseID = "purchase_id"
        case creditsAdded = "credits_added"
        case newBalance = "new_balance"
    }
}

enum CreditsDates {
    /// mako writes RFC 3339 (`2026-10-17T12:00:00+00:00`, with or without fractions) for wallet entries and SQLite's `YYYY-MM-DD HH:MM:SS` (UTC) for older rows. Anything else is nil.
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
            return date
        }
        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: text)
    }
}
