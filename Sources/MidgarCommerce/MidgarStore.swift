import Foundation
import MidgarCore
import StoreKit

/// The purchase engine of a Midgar app (D2): StoreKit 2 on the device, the Midgar ledger as the cross-app record.
///
/// It is an actor, not a `@MainActor` model. The store owns state that several tasks touch (the `Transaction.updates` listener, a purchase, a restore, the background retry) and performs disk and network I/O; an actor serializes all of it without blocking the main thread, and the app wraps ``events()`` in whatever observable model its UI uses.
///
/// - Purchase: every purchase carries `appAccountToken` = the Midgar ID. If the identity cannot answer right now the purchase still proceeds without the token, because a customer's payment must never wait on our backend. The transaction is granted from StoreKit on this device and queued for the ledger, which refuses a transaction without the caller's token (`403 account_mismatch`), so the queue drops it then and the customer keeps the entitlement through StoreKit only.
/// - Money path: a verified transaction is queued on disk, finished, granted, and reported to the ledger in the background until the ledger acknowledges it. An unverified one is never granted, finished or reported.
/// - Entitlements: the union of the ledger's answer for the Midgar ID and StoreKit's `currentEntitlements` on this device.
///
/// RevenueCat coexistence follows the registry engine. `storekit2` and `rc-observer` apps use ``MidgarStoreConfiguration/Mode/purchases``: MidgarCommerce buys, finishes and listens, and RevenueCat, where it is still linked, runs in observer mode (`purchasesAreCompletedBy: .myApp`) and only reports what MidgarCommerce finished. `rc-full` apps use ``MidgarStoreConfiguration/Mode/readOnly`` until their migration: RevenueCat keeps purchasing and finishing, and MidgarCommerce reads the ledger and touches no transaction.
public actor MidgarStore {
    enum Origin {
        case purchase
        case update
    }

    static let retryDelays: [TimeInterval] = [5, 30, 120, 600, 3600]
    static let subscriptionCacheLifetime: TimeInterval = 7 * 24 * 3600

    let configuration: MidgarStoreConfiguration
    let handledProducts: Set<String>
    let identity: any MidgarStoreIdentity
    let ledger: LedgerClient
    let storeKit: any MidgarStoreKit
    let storage: CommerceStorage
    let clock: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
    let signal: @Sendable (String, [String: MidgarSignalValue]) async -> Void
    let log: @Sendable (String) -> Void

    var state: CommerceState
    var localEntitlements: [MidgarEntitlement] = []
    var resolvedEnvironment: StoreEnvironment?
    var seenTransactions: Set<String> = []
    var finishedTransactions: Set<String> = []
    var syncTask: Task<Void, Never>?
    var rerunRequested = false
    var retryTask: Task<Void, Never>?
    var listener: Task<Void, Never>?
    var foreground: ForegroundObserver?
    var subscribers: [UUID: AsyncStream<MidgarStoreEvent>.Continuation] = [:]
    var lastPublished: [MidgarEntitlement] = []
    var isStopped = false

    /// Creates the store, starts the one `Transaction.updates` listener (purchases mode) and refreshes in the background. Create it once at launch and keep it for the life of the process.
    ///
    /// - Parameters:
    ///   - http: The app's gateway client, built from `MidgarIdentity.authorizing(_:)` so every ledger call carries the bearer token.
    ///   - identity: Supplies the Midgar ID for `appAccountToken`.
    public init(
        configuration: MidgarStoreConfiguration,
        identity: any MidgarStoreIdentity,
        http: MidgarHTTPClient,
        logger: @escaping @Sendable (String) -> Void = { MidgarLog.info($0, category: .commerce) }
    ) {
        self.init(
            configuration: configuration,
            identity: identity,
            http: http,
            storeKit: LiveStoreKit(),
            clock: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            signal: { name, props in await MidgarSignals.shared?.record(name, props: props) },
            logger: logger,
            observesForeground: true
        )
    }

    init(
        configuration: MidgarStoreConfiguration,
        identity: any MidgarStoreIdentity,
        http: MidgarHTTPClient,
        storeKit: any MidgarStoreKit,
        clock: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        signal: @escaping @Sendable (String, [String: MidgarSignalValue]) async -> Void,
        logger: @escaping @Sendable (String) -> Void,
        observesForeground: Bool
    ) {
        let storage = CommerceStorage(directory: configuration.directory, appID: configuration.appID)
        self.configuration = configuration
        self.handledProducts = Set(configuration.productIDs)
        self.identity = identity
        self.ledger = LedgerClient(http: http)
        self.storeKit = storeKit
        self.storage = storage
        self.clock = clock
        self.sleep = sleep
        self.signal = signal
        self.log = logger
        self.state = storage.load()
        let updates = configuration.mode == .purchases ? storeKit.updates() : nil
        Task { [weak self] in
            await self?.start(listeningTo: updates, observesForeground: observesForeground)
        }
    }

    /// Starts the one updates listener and the foreground observer, then does the launch refresh.
    private func start(listeningTo updates: AsyncStream<StoreVerification>?, observesForeground: Bool) async {
        guard !isStopped else {
            return
        }
        if let updates {
            listener = Task { [weak self] in
                for await verification in updates {
                    guard let store = self else {
                        return
                    }
                    await store.processUpdate(verification)
                }
            }
        }
        if observesForeground {
            foreground = ForegroundObserver { [weak self] in
                Task { await self?.refresh() }
            }
        }
        await refresh()
    }

    /// Cancels the listener, the retry and the foreground observer. Queued reports stay on disk for the next store.
    public func stop() {
        isStopped = true
        listener?.cancel()
        listener = nil
        retryTask?.cancel()
        retryTask = nil
        foreground = nil
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    /// What the customer may use now: the ledger's answer for this Midgar ID (cached when the ledger is unreachable) united with StoreKit's current entitlements on this device. Lapsed subscriptions are left out against the device clock.
    public var entitlements: [MidgarEntitlement] {
        let date = clock()
        return Self.collapse(localEntitlements.filter { $0.isActive(at: date) } + ledgerEntitlements(at: date))
    }

    public func isEntitled(to name: String) -> Bool {
        entitlements.contains { $0.name == name }
    }

    /// A stream of what changed, one per call. Each subscriber gets its own stream; it ends with ``stop()``.
    public func events() -> AsyncStream<MidgarStoreEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: MidgarStoreEvent.self, bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    /// The configured products with the names and prices StoreKit reports for the customer's storefront.
    public func products() async throws -> [StoreProduct] {
        do {
            return try await storeKit.products(for: configuration.productIDs)
        } catch {
            throw MidgarStoreError.storeKit(String(describing: error))
        }
    }

    /// Buys a configured product. See the type's notes for the identity and money rules.
    public func purchase(_ productID: String) async throws -> MidgarPurchaseResult {
        try requirePurchases()
        guard handledProducts.contains(productID) else {
            throw MidgarStoreError.unknownProduct(productID)
        }
        let token = await accountToken()
        let outcome: StorePurchaseOutcome
        do {
            outcome = try await storeKit.purchase(productID: productID, appAccountToken: token)
        } catch let error as MidgarStoreError {
            throw error
        } catch {
            throw MidgarStoreError.storeKit(String(describing: error))
        }
        switch outcome {
        case .pending:
            log("commerce: purchase of \(productID) is pending approval")
            return .pending
        case .userCancelled:
            return .cancelled
        case .success(let verification):
            try await handle(verification, origin: .purchase)
            return .purchased
        }
    }

    /// Asks the App Store to sync, then re-reads current entitlements, reports each of them to the ledger again and refreshes. The ledger ignores a transaction it already has and raises no sale alert for an old one.
    public func restore() async throws {
        try requirePurchases()
        do {
            try await storeKit.sync()
        } catch {
            throw MidgarStoreError.storeKit(String(describing: error))
        }
        for verification in await storeKit.currentEntitlements() {
            switch verification {
            case .verified(let transaction) where handledProducts.contains(transaction.productID):
                if shouldReport(transaction) {
                    enqueueReport(transaction)
                }
            case .unverified(let transaction, let reason) where handledProducts.contains(transaction.productID):
                log("commerce: restore skipped an unverified transaction for \(transaction.productID): \(reason)")
            default:
                break
            }
        }
        await refresh()
    }

    #if os(iOS) || os(visionOS)
    /// Shows the offer code redemption sheet. The redeemed transaction is handled exactly like any other: on iOS 27 and later the sheet returns it and it goes through the same path as the updates listener, before that the listener delivers it.
    @MainActor
    public func presentOfferCodeRedeemSheet(from viewController: UIViewController) async throws {
        guard configuration.mode == .purchases else {
            throw MidgarStoreError.readOnly
        }
        do {
            if #available(iOS 27.0, visionOS 27.0, *) {
                let result = try await AppStore.presentOfferCodeRedeemSheet(from: viewController)
                try await handle(LiveStoreKit.map(result), origin: .update)
            } else {
                guard let scene = viewController.view.window?.windowScene else {
                    throw MidgarStoreError.unsupportedPlatform
                }
                try await AppStore.presentOfferCodeRedeemSheet(in: scene)
                await refresh()
            }
        } catch let error as MidgarStoreError {
            throw error
        } catch {
            throw MidgarStoreError.storeKit(String(describing: error))
        }
    }
    #endif

    func requirePurchases() throws {
        guard configuration.mode == .purchases else {
            throw MidgarStoreError.readOnly
        }
    }

    /// The Midgar ID as the `appAccountToken`, or nil when the identity cannot answer or its ID is not a UUID. Never throws: a payment does not wait on the identity service.
    func accountToken() async -> UUID? {
        do {
            let id = try await identity.midgarId
            guard let token = UUID(uuidString: id) else {
                log("commerce: the Midgar ID is not a UUID, purchasing without appAccountToken")
                return nil
            }
            return token
        } catch {
            log("commerce: the Midgar ID is unavailable, purchasing without appAccountToken")
            return nil
        }
    }

    func processUpdate(_ verification: StoreVerification) async {
        do {
            try await handle(verification, origin: .update)
        } catch {
            log("commerce: an update could not be processed: \(error)")
        }
    }

    func emit(_ event: MidgarStoreEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}
