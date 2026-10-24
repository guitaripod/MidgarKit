import Foundation
import MidgarCommerce
import MidgarCore

/// AI credit packs on the Midgar ID wallet (P2.09, decision D2). It reads the balance and history of this app's partition of the wallet from mako, sells the configured packs through ``MidgarStore`` (every purchase carries the Midgar ID as `appAccountToken`), and credits a purchase at once through mako's fast-track validation. It replaces the `AICredits` package for MidgarKit 4 apps.
///
/// It is an actor for the same reason ``MidgarStore`` is: a purchase, a background retry and a balance read touch the same state, and none of them may block the main thread. The app wraps ``events()`` in whatever observable model its UI uses.
///
/// - Authentication: Midgar-ID-native, `Authorization: Bearer <access JWT>` alone. An app that still holds an API key for its old per-app balance passes it as `legacyAPIKey`; requests then send `Authorization: Bearer <api key>` and `X-Midgar-Token: <access JWT>`, and mako links that user to the wallet on the first such request.
/// - Money path: the store buys and finishes the consumable. The receipt is then written to disk, validated with mako (`tx:<transaction id>` is the wallet's idempotency key, shared with the webhook, so a purchase credits once however it arrives), and the balance is read again. Validation is retried while mako answers that it will credit shortly; a purchase still unconfirmed after that stays on disk and is retried by ``refresh()`` and in the background.
/// - Packs: ids, product ids and credit amounts come from ``MidgarCreditsConfiguration``. Nothing is inferred from a product id.
public actor MidgarCredits {
    static let validationDelays: [TimeInterval] = [2, 5, 15]
    static let reconcileDelays: [TimeInterval] = [30, 120, 600, 1800]
    static let pendingLifetime: TimeInterval = 7 * 24 * 3600

    let configuration: MidgarCreditsConfiguration
    let api: CreditsAPI
    let purchasing: any MidgarCreditsPurchasing
    let pendingStore: CreditsPendingStore
    let clock: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
    let log: @Sendable (String) -> Void
    let reconciles: Bool

    var cachedBalance: MidgarCreditsBalance?
    var pending: [PendingCredit]
    var settling: Set<String> = []
    var subscribers: [UUID: AsyncStream<MidgarCreditsEvent>.Continuation] = [:]
    var reconcileTask: Task<Void, Never>?
    var eventsTask: Task<Void, Never>?
    var isStopped = false

    /// Creates the wallet client, starts listening for approved purchases and refreshes in the background. Create it once at launch and keep it for the life of the process.
    ///
    /// - Parameters:
    ///   - http: The app's gateway configuration, without a token provider. MidgarCredits authorizes it itself, because a legacy key and the Midgar token travel in different headers.
    ///   - identity: Supplies the access token. ``MidgarIdentity`` conforms.
    ///   - purchasing: Sells the packs. ``MidgarStore`` conforms; its configuration must list ``MidgarCreditsConfiguration/productIDs``.
    ///   - legacyAPIKey: The app's old per-app API key, read on every request, or nil. A nil result means that request is Midgar-ID-native.
    public init(
        configuration: MidgarCreditsConfiguration,
        http: MidgarHTTPConfiguration,
        identity: any MidgarCreditsIdentity,
        purchasing: any MidgarCreditsPurchasing,
        legacyAPIKey: (@Sendable () async -> String?)? = nil,
        logger: @escaping @Sendable (String) -> Void = { MidgarLog.info($0, category: .commerce) }
    ) {
        self.init(
            configuration: configuration,
            http: http,
            identity: identity,
            purchasing: purchasing,
            legacyAPIKey: legacyAPIKey,
            clock: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            logger: logger,
            reconciles: true,
            startsRefreshing: true
        )
    }

    init(
        configuration: MidgarCreditsConfiguration,
        http: MidgarHTTPConfiguration,
        identity: any MidgarCreditsIdentity,
        purchasing: any MidgarCreditsPurchasing,
        legacyAPIKey: (@Sendable () async -> String?)?,
        clock: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        logger: @escaping @Sendable (String) -> Void,
        reconciles: Bool,
        startsRefreshing: Bool
    ) {
        let store = CreditsPendingStore(directory: configuration.directory, appID: http.appID)
        self.configuration = configuration
        self.api = CreditsAPI(configuration: http, identity: identity, legacyAPIKey: legacyAPIKey)
        self.purchasing = purchasing
        self.pendingStore = store
        self.clock = clock
        self.sleep = sleep
        self.log = logger
        self.reconciles = reconciles
        self.pending = store.load()
        if startsRefreshing {
            Task { [weak self] in
                await self?.start()
            }
        }
    }

    /// Starts the listener for purchases approved outside this process's own `buy` (Ask to Buy), then refreshes.
    func start() async {
        guard !isStopped else {
            return
        }
        let stream = await purchasing.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard case .purchaseApproved(let productID) = event else {
                    continue
                }
                await self?.purchaseWasApproved(productID)
            }
        }
        _ = try? await refresh()
    }

    /// Cancels the listener and the background retry and ends every event stream. Unconfirmed purchases stay on disk for the next instance.
    public func stop() {
        isStopped = true
        eventsTask?.cancel()
        eventsTask = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    /// The packs this app sells, from the configuration.
    public nonisolated var packs: [MidgarCreditsPack] {
        configuration.packs
    }

    /// The last balance mako confirmed in this process, or nil before the first read.
    public var balance: MidgarCreditsBalance? {
        cachedBalance
    }

    /// How many paid purchases mako has not confirmed yet.
    public var unconfirmedPurchases: Int {
        pending.count
    }

    /// A stream of what changed, one per call. Each subscriber gets its own stream; it ends with ``stop()``.
    public func events() -> AsyncStream<MidgarCreditsEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: MidgarCreditsEvent.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// Settles purchases mako has not confirmed (one attempt each), then reads the balance. Call it at launch, when the app comes to the foreground and before a screen shows the balance.
    ///
    /// - Throws: ``MidgarCreditsError``, or `CancellationError`.
    @discardableResult
    public func refresh() async throws -> MidgarCreditsBalance {
        await settlePending()
        return try await readBalance()
    }

    /// One page of the wallet's history for this app, newest first. mako caps a page at 100.
    public func transactions(page: Int = 1, perPage: Int = 50) async throws -> MidgarCreditsTransactionPage {
        let wire = try await api.transactions(page: max(1, page), perPage: min(max(1, perPage), 100))
        return MidgarCreditsTransactionPage(
            transactions: wire.transactions.map {
                MidgarCreditsTransaction(
                    id: $0.id,
                    kind: $0.type,
                    amount: $0.amount,
                    balanceAfter: $0.balanceAfter,
                    description: $0.description,
                    reference: $0.referenceID,
                    date: CreditsDates.parse($0.createdAt)
                )
            },
            total: wire.total,
            page: wire.page ?? max(1, page),
            perPage: wire.perPage ?? min(max(1, perPage), 100)
        )
    }

    /// The configured packs with the names and prices StoreKit reports for the customer's storefront. A pack StoreKit does not sell is left out.
    public func offers() async throws -> [MidgarCreditsOffer] {
        let products: [StoreProduct]
        do {
            products = try await purchasing.products()
        } catch let error as MidgarStoreError {
            throw MidgarCreditsError.store(error)
        }
        let byID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return configuration.packs.compactMap { pack in
            byID[pack.productID].map { MidgarCreditsOffer(pack: pack, product: $0) }
        }
    }

    /// Maps a failure of a metered call (MidgarIntelligence's, which answers 402 when the wallet is empty) to this module's errors. A 402 becomes ``MidgarCreditsError/insufficientCredits(balance:)`` with the wallet balance read now; cancellation stays `CancellationError`.
    public func creditsError(for error: MidgarHTTPError) async -> any Error {
        await api.translated(error)
    }

    func readBalance() async throws -> MidgarCreditsBalance {
        let wire = try await api.balance()
        let allowances = wire.allowances.map {
            MidgarCreditsAllowance(id: $0.id, remaining: max(0, $0.remaining), limit: max(0, $0.limit), resetsAt: CreditsDates.parse($0.resetsAt))
        }
        return record(credits: wire.balance, allowances: allowances)
    }

    /// Stores a balance mako confirmed and tells observers when it or its allowances differ from the last one. A caller that has no allowances to report (the validation's `new_balance`) keeps the ones already known.
    @discardableResult
    func record(credits: Int, allowances: [MidgarCreditsAllowance]? = nil) -> MidgarCreditsBalance {
        let balance = MidgarCreditsBalance(
            credits: credits,
            updatedAt: clock(),
            allowances: allowances ?? cachedBalance?.allowances ?? []
        )
        let changed = cachedBalance?.credits != credits || cachedBalance?.allowances != balance.allowances
        cachedBalance = balance
        if changed {
            emit(.balanceChanged(balance))
        }
        return balance
    }

    func emit(_ event: MidgarCreditsEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func purchaseWasApproved(_ productID: String) async {
        guard configuration.packs.contains(where: { $0.productID == productID }) else {
            return
        }
        _ = try? await refresh()
    }
}
