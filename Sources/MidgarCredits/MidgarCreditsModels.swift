import Foundation
import MidgarCommerce

/// The credits this app can spend, as mako reports them for the Midgar ID.
public struct MidgarCreditsBalance: Sendable, Equatable {
    public let credits: Int
    public let updatedAt: Date
    /// The free allowances mako reports next to the balance, sorted by ``MidgarCreditsAllowance/id``. Empty for an app without any, and for a mako that does not send them.
    public let allowances: [MidgarCreditsAllowance]

    public init(credits: Int, updatedAt: Date, allowances: [MidgarCreditsAllowance] = []) {
        self.credits = credits
        self.updatedAt = updatedAt
        self.allowances = allowances
    }
}

/// One free allowance that renews on a schedule, such as the weekly free uses of a capability. mako sends them as `weekly` on the balance, keyed by the capability or alias id.
public struct MidgarCreditsAllowance: Sendable, Equatable, Identifiable {
    /// The capability or bucket id mako keys the allowance by (`reading.v2`).
    public let id: String
    /// What is left in the current period. Never negative.
    public let remaining: Int
    /// What the period starts with.
    public let limit: Int
    /// When the allowance refills, or nil when mako sent no date or one that cannot be read.
    public let resetsAt: Date?

    public init(id: String, remaining: Int, limit: Int, resetsAt: Date?) {
        self.id = id
        self.remaining = remaining
        self.limit = limit
        self.resetsAt = resetsAt
    }
}

/// One line of the wallet's history for this app, newest first.
public struct MidgarCreditsTransaction: Sendable, Equatable, Identifiable {
    public let id: String
    /// mako's type: `purchase`, `bonus`, `migrate`, `spend`, `refund` or `admin_adjustment`. Unknown types are passed through.
    public let kind: String
    /// Signed: negative for a spend.
    public let amount: Int
    public let balanceAfter: Int
    public let description: String
    public let reference: String?
    public let date: Date?

    public init(id: String, kind: String, amount: Int, balanceAfter: Int, description: String, reference: String?, date: Date?) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.balanceAfter = balanceAfter
        self.description = description
        self.reference = reference
        self.date = date
    }
}

/// One page of ``MidgarCreditsTransaction``s.
public struct MidgarCreditsTransactionPage: Sendable, Equatable {
    public let transactions: [MidgarCreditsTransaction]
    public let total: Int
    public let page: Int
    public let perPage: Int

    public init(transactions: [MidgarCreditsTransaction], total: Int, page: Int, perPage: Int) {
        self.transactions = transactions
        self.total = total
        self.page = page
        self.perPage = perPage
    }

    public var hasMore: Bool {
        page * perPage < total
    }
}

/// A pack with the name and price StoreKit reports for the customer's storefront.
public struct MidgarCreditsOffer: Sendable, Equatable, Identifiable {
    public let pack: MidgarCreditsPack
    public let product: StoreProduct

    public var id: String { pack.id }

    public init(pack: MidgarCreditsPack, product: StoreProduct) {
        self.pack = pack
        self.product = product
    }
}

/// What buying a pack ended in when it did not throw.
public enum MidgarCreditsPurchaseResult: Sendable, Equatable {
    /// mako confirmed the credit. `balance` is the wallet balance after it.
    case credited(packID: String, creditsAdded: Int, balance: Int)
    /// The customer paid and the transaction is finished, but mako has not confirmed the credit yet (offline, the wallet is busy, or the purchase has not reached the verifier). It is kept on disk and retried on every ``MidgarCredits/refresh()``; the webhook credits it as well, and the two cannot double-credit.
    case creditPending(packID: String, credits: Int)
    /// Ask to Buy or another approval is pending. The approved purchase credits through the webhook; ``MidgarCredits/refresh()`` picks the balance up.
    case awaitingApproval
    case cancelled
}

/// What ``MidgarCredits/events()`` tells observers.
public enum MidgarCreditsEvent: Sendable, Equatable {
    case balanceChanged(MidgarCreditsBalance)
    case purchaseCredited(packID: String, creditsAdded: Int)
}
