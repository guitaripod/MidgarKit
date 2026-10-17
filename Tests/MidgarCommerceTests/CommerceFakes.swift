import Foundation
import MidgarCore
@testable import MidgarCommerce

enum Products {
    static let pro = "app.midgar.test.pro"
    static let monthly = "app.midgar.test.monthly"
    static let credits = "app.midgar.test.credits"
}

let commerceEpoch = Date(timeIntervalSince1970: 1_800_000_000)

/// A clock the test moves by hand. `current` is touched only inside `lock`.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = commerceEpoch

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// The Midgar ID the test controls. `value` is touched only inside `lock`.
final class FakeIdentity: MidgarStoreIdentity, @unchecked Sendable {
    struct Unavailable: Error {}

    static let first = "8F1C3C5E-1B3A-4E57-9A53-2B7E6D1F0A11"
    static let second = "0D5B2A3C-77C1-4F0B-8E54-9C6A1B2D3E44"

    private let lock = NSLock()
    private var value: String?

    init(_ value: String? = FakeIdentity.first) {
        self.value = value
    }

    func set(_ newValue: String?) { lock.withLock { value = newValue } }

    var midgarId: String {
        get async throws {
            guard let id = lock.withLock({ value }) else {
                throw Unavailable()
            }
            return id
        }
    }
}

/// Counts and records every `finish()` call. `finished` is touched only inside `lock`.
final class FinishLog: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: [UInt64] = []

    var ids: [UInt64] { lock.withLock { finished } }

    func record(_ id: UInt64) { lock.withLock { finished.append(id) } }
}

/// A scripted StoreKit. Every field is touched only inside `lock`; the update stream is created once and buffers unread values.
final class FakeStoreKit: MidgarStoreKit, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [StorePurchaseOutcome] = []
    private var current: [StoreVerification] = []
    private var purchaseCalls: [(productID: String, token: UUID?, confirmed: Bool)] = []
    private var syncCalls = 0
    private var environment: StoreEnvironment?
    private var catalog: [String: StoreProduct] = [:]
    private let stream: AsyncStream<StoreVerification>
    private let continuation: AsyncStream<StoreVerification>.Continuation

    init(environment: StoreEnvironment? = .production) {
        self.environment = environment
        (stream, continuation) = AsyncStream.makeStream()
    }

    var purchases: [(productID: String, token: UUID?, confirmed: Bool)] { lock.withLock { purchaseCalls } }
    var syncCount: Int { lock.withLock { syncCalls } }

    func queue(_ outcome: StorePurchaseOutcome) { lock.withLock { outcomes.append(outcome) } }
    func setCurrent(_ verifications: [StoreVerification]) { lock.withLock { current = verifications } }
    func emit(_ verification: StoreVerification) { continuation.yield(verification) }
    func setCatalog(_ products: [StoreProduct]) { lock.withLock { catalog = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) }) } }

    func products(for ids: [String]) async throws -> [StoreProduct] {
        lock.withLock {
            ids.map { catalog[$0] ?? StoreProduct(id: $0, displayName: $0, description: "", displayPrice: "$1") }
        }
    }

    func purchase(productID: String, appAccountToken: UUID?, confirmation: StoreConfirmation?) async throws -> StorePurchaseOutcome {
        lock.withLock {
            purchaseCalls.append((productID, appAccountToken, confirmation != nil))
            return outcomes.isEmpty ? .userCancelled : outcomes.removeFirst()
        }
    }

    func updates() -> AsyncStream<StoreVerification> { stream }

    func currentEntitlements() async -> [StoreVerification] { lock.withLock { current } }

    func sync() async throws { lock.withLock { syncCalls += 1 } }

    func appEnvironment() async -> StoreEnvironment? { lock.withLock { environment } }
}

func makeTransaction(
    id: UInt64 = 1,
    original: UInt64? = nil,
    product: String = Products.pro,
    kind: StoreProductKind = .nonConsumable,
    expires: Date? = nil,
    revoked: Date? = nil,
    ownership: StoreOwnership = .purchased,
    token: UUID? = UUID(uuidString: FakeIdentity.first),
    environment: StoreEnvironment = .production,
    log: FinishLog
) -> StoreTransaction {
    StoreTransaction(
        id: id,
        originalID: original ?? id,
        productID: product,
        kind: kind,
        purchaseDate: commerceEpoch,
        expirationDate: expires,
        revocationDate: revoked,
        isUpgraded: false,
        ownership: ownership,
        appAccountToken: token,
        environment: environment,
        jws: "jws-\(id)-\(revoked != nil ? "revoked" : "active")",
        finish: { log.record(id) }
    )
}

/// Collects the store's log lines. `captured` is touched only inside `lock`.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []

    var lines: [String] { lock.withLock { captured } }

    func record(_ line: String) { lock.withLock { captured.append(line) } }
}

actor SignalCapture {
    private(set) var events: [(name: String, props: [String: MidgarSignalValue])] = []

    func record(_ name: String, _ props: [String: MidgarSignalValue]) {
        events.append((name, props))
    }
}

/// Holds every background sleep until the test releases it. `waiters` is touched only inside `lock`.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, any Error>] = []
    private var durations: [Duration] = []

    var requested: [Duration] { lock.withLock { durations } }

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                durations.append(duration)
                waiters.append(continuation)
            }
        }
    }

    func releaseAll() {
        let released = lock.withLock { () -> [CheckedContinuation<Void, any Error>] in
            defer { waiters = [] }
            return waiters
        }
        for waiter in released {
            waiter.resume()
        }
    }
}

/// One store under test with every collaborator the test may inspect.
struct StoreHarness {
    let store: MidgarStore
    let storeKit: FakeStoreKit
    let ledger: FakeLedger
    let identity: FakeIdentity
    let clock: TestClock
    let finishes: FinishLog
    let logs: LogCapture
    let signals: SignalCapture
    let sleeper: ManualSleeper
    let directory: URL

    static let entitlementMap = [Products.pro: "pro", Products.monthly: "pro"]

    init(
        mode: MidgarStoreConfiguration.Mode = .purchases,
        crossAppEntitlements: Set<String> = [],
        storeKit: FakeStoreKit = FakeStoreKit(),
        ledger: FakeLedger = FakeLedger(),
        identity: FakeIdentity = FakeIdentity(),
        clock: TestClock = TestClock(),
        finishes: FinishLog = FinishLog(),
        sleeper: ManualSleeper = ManualSleeper(),
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("commerce-" + UUID().uuidString, isDirectory: true)
    ) {
        let logs = LogCapture()
        let signals = SignalCapture()
        self.storeKit = storeKit
        self.ledger = ledger
        self.identity = identity
        self.clock = clock
        self.finishes = finishes
        self.logs = logs
        self.signals = signals
        self.sleeper = sleeper
        self.directory = directory
        store = MidgarStore(
            configuration: MidgarStoreConfiguration(
                appID: "app-test",
                productIDs: [Products.pro, Products.monthly],
                entitlementsByProduct: Self.entitlementMap,
                mode: mode,
                crossAppEntitlements: crossAppEntitlements,
                directory: directory
            ),
            identity: identity,
            http: makeStubClient(ledger, tokenProvider: { try await identity.midgarId }),
            storeKit: storeKit,
            clock: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            signal: { await signals.record($0, $1) },
            logger: { logs.record($0) },
            observesForeground: false
        )
    }

    func transaction(
        id: UInt64 = 1,
        original: UInt64? = nil,
        product: String = Products.pro,
        kind: StoreProductKind = .nonConsumable,
        expires: Date? = nil,
        revoked: Date? = nil,
        ownership: StoreOwnership = .purchased,
        token: UUID? = UUID(uuidString: FakeIdentity.first),
        environment: StoreEnvironment = .production
    ) -> StoreTransaction {
        makeTransaction(
            id: id, original: original, product: product, kind: kind, expires: expires, revoked: revoked,
            ownership: ownership, token: token, environment: environment, log: finishes
        )
    }

    var pendingReports: [PendingReport] {
        CommerceStorage(directory: directory, appID: "app-test").load().pending
    }

    var storedLedger: LedgerSnapshot? {
        CommerceStorage(directory: directory, appID: "app-test").load().ledger
    }
}

/// Polls until the condition holds or five seconds pass, for work that runs on the store's own tasks.
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
