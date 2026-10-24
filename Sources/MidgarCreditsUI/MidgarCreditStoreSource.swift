import MidgarCredits

/// What ``MidgarCreditStoreView`` needs from the wallet. ``MidgarCredits`` is the production conformance; previews and tests pass a fake.
public protocol MidgarCreditStoreSource: Sendable {
    /// The last balance the wallet confirmed in this process, or nil before the first read.
    var balance: MidgarCreditsBalance? { get async }
    /// How many paid purchases the wallet has not confirmed yet.
    var unconfirmedPurchases: Int { get async }
    func refresh() async throws -> MidgarCreditsBalance
    func offers() async throws -> [MidgarCreditsOffer]
    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult
    func events() async -> AsyncStream<MidgarCreditsEvent>
}

extension MidgarCredits: MidgarCreditStoreSource {}
