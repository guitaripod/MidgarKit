import Foundation

extension MidgarStore {
    /// How long an Ask to Buy may wait for its approval and still count as a purchase made here.
    static let approvalLifetime: TimeInterval = 30 * 24 * 3600
    /// How long after an offer code sheet was shown a new transaction still counts as redeemed here.
    static let redemptionLifetime: TimeInterval = 3600

    /// Remembers that this install started a purchase the App Store will complete later, so the transaction counts as a purchase made here when it arrives through the updates listener. Written to disk, because an approval can take days. `productID` is nil when the sheet does not say which product was chosen.
    func expectPurchase(of productID: String?, for lifetime: TimeInterval) {
        var awaited = unexpired(state.awaited ?? [])
        awaited.removeAll { $0.productID == productID }
        awaited.append(AwaitedPurchase(productID: productID, until: clock().addingTimeInterval(lifetime)))
        state.awaited = awaited
        persist()
    }

    /// True, once, when a new transaction is one this install was waiting for: its own product first, else a sheet that could have sold any product. A transaction nobody here was waiting for was bought on another device or outside the app, and is not a purchase this install made.
    func claimExpected(_ transaction: StoreTransaction) -> Bool {
        var awaited = unexpired(state.awaited ?? [])
        let match = awaited.firstIndex { $0.productID == transaction.productID } ?? awaited.firstIndex { $0.productID == nil }
        if let match {
            awaited.remove(at: match)
        }
        if awaited != (state.awaited ?? []) {
            state.awaited = awaited.isEmpty ? nil : awaited
            persist()
        }
        return match != nil
    }

    private func unexpired(_ awaited: [AwaitedPurchase]) -> [AwaitedPurchase] {
        let now = clock()
        return awaited.filter { $0.until > now }
    }
}
