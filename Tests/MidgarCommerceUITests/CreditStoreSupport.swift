import Foundation
import MidgarCommerce
import MidgarCredits
@testable import MidgarCommerceUI

/// A wallet the test scripts. Everything is touched only inside `lock`.
final class FakeCreditSource: MidgarCreditStoreSource, @unchecked Sendable {
    struct Unreachable: Error {}

    private let lock = NSLock()
    private var currentBalance: MidgarCreditsBalance?
    private var refreshFailure: (any Error)?
    private var catalog: [MidgarCreditsOffer] = []
    private var offersFailure: (any Error)?
    private var results: [Result<MidgarCreditsPurchaseResult, any Error>] = []
    private var bought: [String] = []
    private var held = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var unconfirmed = 0
    private let stream: AsyncStream<MidgarCreditsEvent>
    private let continuation: AsyncStream<MidgarCreditsEvent>.Continuation

    init(balance: MidgarCreditsBalance? = MidgarCreditsBalance(credits: 128, updatedAt: Date(timeIntervalSince1970: 0)), offers: [MidgarCreditsOffer] = CreditFixtures.offers) {
        currentBalance = balance
        catalog = offers
        (stream, continuation) = AsyncStream.makeStream()
    }

    var balance: MidgarCreditsBalance? { get async { lock.withLock { currentBalance } } }
    var unconfirmedPurchases: Int { get async { lock.withLock { unconfirmed } } }
    var purchased: [String] { lock.withLock { bought } }

    func setBalance(_ balance: MidgarCreditsBalance?) { lock.withLock { currentBalance = balance } }
    func setRefreshFailure(_ error: (any Error)?) { lock.withLock { refreshFailure = error } }
    func setOffers(_ offers: [MidgarCreditsOffer]) { lock.withLock { catalog = offers } }
    func setOffersFailure(_ error: (any Error)?) { lock.withLock { offersFailure = error } }
    func setUnconfirmed(_ count: Int) { lock.withLock { unconfirmed = count } }
    func queue(_ result: MidgarCreditsPurchaseResult) { lock.withLock { results.append(.success(result)) } }
    func queue(failure: any Error) { lock.withLock { results.append(.failure(failure)) } }
    func holdPurchases(_ hold: Bool) { lock.withLock { held = hold } }
    func emit(_ event: MidgarCreditsEvent) { continuation.yield(event) }
    func finishEvents() { continuation.finish() }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { waiting = nil }
            return waiting
        }
        pending?.resume()
    }

    func refresh() async throws -> MidgarCreditsBalance {
        let (failure, balance) = lock.withLock { (refreshFailure, currentBalance) }
        if let failure {
            throw failure
        }
        return try balance ?? { throw Unreachable() }()
    }

    func offers() async throws -> [MidgarCreditsOffer] {
        let (failure, offers) = lock.withLock { (offersFailure, catalog) }
        if let failure {
            throw failure
        }
        return offers
    }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        let hold = lock.withLock { () -> Bool in
            bought.append(packID)
            return held
        }
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { waiting = continuation }
            }
        }
        let next = lock.withLock { () -> Result<MidgarCreditsPurchaseResult, any Error> in
            results.isEmpty ? .success(.cancelled) : results.removeFirst()
        }
        return try next.get()
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> { stream }
}

enum CreditFixtures {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    static func offer(_ id: String, credits: Int, name: String, price: String) -> MidgarCreditsOffer {
        MidgarCreditsOffer(
            pack: MidgarCreditsPack(id: id, productID: "app.midgar.test.credits.\(id)", credits: credits),
            product: StoreProduct(id: "app.midgar.test.credits.\(id)", displayName: name, description: "", displayPrice: price)
        )
    }

    static let starter = offer("starter", credits: 150, name: "Starter pack", price: "$2.99")
    static let plus = offer("plus", credits: 700, name: "Plus pack", price: "$9.99")
    static let max = offer("max", credits: 3000, name: "Max pack with a rather long name for the row", price: "$34.99")
    static let offers = [starter, plus, max]

    static let allowances = [
        MidgarCreditsAllowance(id: "chat.haiku", remaining: 7, limit: 10, resetsAt: Date(timeIntervalSince1970: 1_791_763_200)),
        MidgarCreditsAllowance(id: "reading.v2", remaining: 0, limit: 3, resetsAt: Date(timeIntervalSince1970: 1_791_763_200))
    ]

    static func balance(_ credits: Int, allowances: [MidgarCreditsAllowance] = []) -> MidgarCreditsBalance {
        MidgarCreditsBalance(credits: credits, updatedAt: epoch, allowances: allowances)
    }
}
