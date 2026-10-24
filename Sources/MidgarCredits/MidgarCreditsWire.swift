import Foundation

/// The body of mako's `GET /v1/credits/balance`: `{"balance": 12, "currency": "credits", "weekly": {"<alias>": {"limit": 3, "remaining": 2, "resets_at": "2026-10-12T00:00:00Z"}}}`. `weekly` is absent for an app without weekly free buckets. A bucket that does not parse is skipped, so one bad entry never hides the balance.
struct CreditsBalanceWire: Decodable, Sendable {
    let balance: Int
    let allowances: [CreditsAllowanceWire]

    enum CodingKeys: String, CodingKey {
        case balance
        case weekly
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        balance = try container.decode(Int.self, forKey: .balance)
        let buckets = (try? container.decodeIfPresent([String: LossyBucket].self, forKey: .weekly)) ?? [:]
        allowances = buckets
            .compactMap { id, bucket in bucket.value.map { CreditsAllowanceWire(id: id, limit: $0.limit, remaining: $0.remaining, resetsAt: $0.resetsAt) } }
            .sorted { $0.id < $1.id }
    }

    private struct LossyBucket: Decodable {
        let value: Bucket?

        init(from decoder: any Decoder) throws {
            value = try? Bucket(from: decoder)
        }
    }

    private struct Bucket: Decodable {
        let limit: Int
        let remaining: Int
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case limit
            case remaining
            case resetsAt = "resets_at"
        }
    }
}

struct CreditsAllowanceWire: Sendable, Equatable {
    let id: String
    let limit: Int
    let remaining: Int
    let resetsAt: String?
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

/// The body of mako's `POST /v1/credits/purchase/revenuecat/validate`. mako identifies the purchase by `purchase_token`, the App Store transaction id (RevenueCat's `store_purchase_identifier`), and binds the price to the credits through `pack_id` and `product_id`. `platform` is `ios` on every Apple platform: mako only knows `ios` and `android`. `signed_transaction` is the StoreKit 2 JWS: mako has the ledger verify it instead of asking RevenueCat, and credits the pack under the same `tx:<transaction id>` key.
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

/// The body of mako's `POST /v1/attribution`: the AdServices token, as `attribution_token`. mako also reads `app_id`, which must match the caller's app when present, so it is left out.
struct CreditsAttributionBody: Encodable, Sendable {
    let attributionToken: String

    enum CodingKeys: String, CodingKey {
        case attributionToken = "attribution_token"
    }
}

/// mako's answer: `{"status": "attributed" | "organic" | "duplicate" | "pending" | "invalid" | "unavailable", "attributed": bool, "retry_after_seconds": 5}`. The last field is only present while the status is `pending`.
struct CreditsAttributionWire: Decodable, Sendable {
    let status: String
    let retryAfterSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case status
        case retryAfterSeconds = "retry_after_seconds"
    }
}
