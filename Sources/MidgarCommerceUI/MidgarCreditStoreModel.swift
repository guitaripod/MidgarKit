import Foundation
import MidgarCredits
import Observation

/// Why a purchase or a load failed, in the few cases a person can act on. Every case has one short message.
enum MidgarCreditStoreFailure: Equatable {
    case offline
    case walletUnavailable
    case signIn
    case rateLimited
    case rejected
    case unavailable
    case generic

    init(_ error: any Error) {
        guard let credits = error as? MidgarCreditsError else {
            self = .generic
            return
        }
        switch credits {
        case .offline:
            self = .offline
        case .walletUnavailable:
            self = .walletUnavailable
        case .unauthorized, .identityUnavailable:
            self = .signIn
        case .rateLimited:
            self = .rateLimited
        case .purchaseRejected:
            self = .rejected
        case .notConfigured:
            self = .unavailable
        case .insufficientCredits, .store, .server, .invalidResponse:
            self = .generic
        @unknown default:
            self = .generic
        }
    }

    var message: String {
        switch self {
        case .offline:
            return MidgarCommerceUIStrings.creditsOffline
        case .walletUnavailable:
            return MidgarCommerceUIStrings.creditsWalletUnavailable
        case .signIn:
            return MidgarCommerceUIStrings.creditsSignIn
        case .rateLimited:
            return MidgarCommerceUIStrings.creditsRateLimited
        case .rejected:
            return MidgarCommerceUIStrings.creditsRejected
        case .unavailable:
            return MidgarCommerceUIStrings.creditsPacksNotAvailable
        case .generic:
            return MidgarCommerceUIStrings.purchaseFailed
        }
    }
}

/// The state of ``MidgarCreditStoreView``: the balance, the packs, the purchase in progress, the purchases still being confirmed and the message about the last result. The views only draw it.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
@MainActor @Observable
final class MidgarCreditStoreModel {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable
    }

    /// A paid purchase the wallet has not credited. `packID` and `credits` are nil for one made in an earlier launch, which is only known by its count.
    struct Confirming: Identifiable, Equatable {
        let id = UUID()
        let packID: String?
        let credits: Int?
    }

    enum Notice: Equatable {
        case credited(Int)
        case awaitingApproval
        case failure(MidgarCreditStoreFailure)
    }

    @ObservationIgnored private let source: any MidgarCreditStoreSource
    let shortfall: Int?

    private(set) var phase = Phase.loading
    private(set) var balance: MidgarCreditsBalance?
    private(set) var balanceUnavailable = false
    private(set) var offers: [MidgarCreditsOffer] = []
    private(set) var buyingPackID: String?
    private(set) var confirming: [Confirming] = []
    private(set) var notice: Notice?

    init(source: any MidgarCreditStoreSource, shortfall: Int?) {
        self.source = source
        self.shortfall = shortfall.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The smallest pack that covers the shortfall, which the list marks. Nil without a shortfall or when no single pack covers it.
    var coveringPackID: String? {
        guard let shortfall else {
            return nil
        }
        return offers
            .filter { $0.pack.credits >= shortfall }
            .min { $0.pack.credits < $1.pack.credits }?
            .pack.id
    }

    var isBuying: Bool {
        buyingPackID != nil
    }

    /// Reads the balance and the packs together, then picks up the purchases an earlier launch left unconfirmed. A failure of one does not hide the other.
    func load() async {
        let source = source
        async let refreshed = Self.attempt { try await source.refresh() }
        async let loaded = Self.attempt { try await source.offers() }
        let (balanceResult, offersResult) = await (refreshed, loaded)
        guard !Task.isCancelled else {
            return
        }
        await apply(balanceResult)
        apply(offersResult)
        await reconcileConfirming()
    }

    /// Shows the spinner again, then loads: what Try again does after the packs could not be loaded.
    func retry() async {
        phase = .loading
        await load()
    }

    private func apply(_ result: Result<MidgarCreditsBalance, any Error>) async {
        switch result {
        case .success(let read):
            balance = read
            balanceUnavailable = false
        case .failure:
            balance = await source.balance ?? balance
            balanceUnavailable = balance == nil
        }
    }

    private func apply(_ result: Result<[MidgarCreditsOffer], any Error>) {
        if case .success(let loaded) = result {
            offers = loaded
        }
        phase = offers.isEmpty ? .unavailable : .ready
    }

    /// Follows what the wallet reports until the stream ends. Run it for as long as the view is on screen.
    func observe() async {
        for await event in await source.events() {
            await handle(event)
        }
    }

    func handle(_ event: MidgarCreditsEvent) async {
        switch event {
        case .balanceChanged(let changed):
            balance = changed
            balanceUnavailable = false
        case .purchaseCredited(let packID, let added):
            if let index = confirming.firstIndex(where: { $0.packID == packID }) {
                confirming.remove(at: index)
                notice = .credited(added)
            }
            await reconcileConfirming()
        }
    }

    /// Buys the pack and records what came of it. Cancelling does nothing visible; the other results become the balance, a confirming row or a message.
    func buy(_ offer: MidgarCreditsOffer) async {
        guard buyingPackID == nil else {
            return
        }
        buyingPackID = offer.pack.id
        notice = nil
        defer { buyingPackID = nil }
        do {
            switch try await source.buy(offer.pack.id) {
            case .credited(_, let added, let newBalance):
                await adoptBalance(newBalance)
                notice = .credited(added)
            case .creditPending(let packID, let credits):
                confirming.append(Confirming(packID: packID, credits: credits))
            case .awaitingApproval:
                notice = .awaitingApproval
            case .cancelled:
                break
            }
        } catch is CancellationError {
            return
        } catch {
            notice = .failure(MidgarCreditStoreFailure(error))
        }
    }

    private func adoptBalance(_ credits: Int) async {
        if let known = await source.balance, known.credits == credits {
            balance = known
        } else {
            balance = MidgarCreditsBalance(credits: credits, updatedAt: Date(), allowances: balance?.allowances ?? [])
        }
        balanceUnavailable = false
    }

    /// Makes the confirming rows match how many purchases the wallet still holds: rows for purchases made before this view existed are added, and rows the wallet has since credited are dropped, those of unknown pack first.
    private func reconcileConfirming() async {
        let held = await source.unconfirmedPurchases
        while confirming.count < held {
            confirming.append(Confirming(packID: nil, credits: nil))
        }
        while confirming.count > held {
            let index = confirming.firstIndex { $0.packID == nil } ?? 0
            confirming.remove(at: index)
        }
    }

    nonisolated private static func attempt<Value: Sendable>(_ work: @Sendable () async throws -> Value) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
