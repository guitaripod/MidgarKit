import Foundation
import MidgarCommerce
import MidgarCore
@testable import MidgarCredits

enum CreditsProducts {
    static let starter = "app.midgar.test.credits.starter"
    static let plus = "app.midgar.test.credits.plus"
}

let creditsPacks = [
    MidgarCreditsPack(id: "starter", productID: CreditsProducts.starter, credits: 150),
    MidgarCreditsPack(id: "plus", productID: CreditsProducts.plus, credits: 700)
]

let creditsEpoch = Date(timeIntervalSince1970: 1_800_000_000)

func creditsReceipt(id: String = "1001", product: String = CreditsProducts.starter) -> MidgarPurchaseReceipt {
    MidgarPurchaseReceipt(productID: product, transactionID: id, signedTransaction: "jws-\(id)", environment: "production")
}

/// The identity the test controls. `token` and `failure` are touched only inside `lock`.
final class FakeCreditsIdentity: MidgarCreditsIdentity, @unchecked Sendable {
    struct Unavailable: Error {}

    private let lock = NSLock()
    private var token: String? = "jwt-1"
    private var invalidations = 0

    func set(_ newToken: String?) { lock.withLock { token = newToken } }
    var invalidationCount: Int { lock.withLock { invalidations } }

    func accessToken() async throws -> String {
        guard let token = lock.withLock({ token }) else {
            throw Unavailable()
        }
        return token
    }

    func invalidateAccessToken() async {
        lock.withLock { invalidations += 1 }
    }
}

/// A scripted store. Results come off a queue; an empty queue means the customer cancelled. All fields are touched only inside `lock`.
final class FakeCreditsStore: MidgarCreditsPurchasing, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<MidgarReceiptResult, MidgarStoreError>] = []
    private var bought: [String] = []
    private var catalog: [StoreProduct] = []
    private let stream: AsyncStream<MidgarStoreEvent>
    private let continuation: AsyncStream<MidgarStoreEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    var purchased: [String] { lock.withLock { bought } }

    func queue(_ result: MidgarReceiptResult) { lock.withLock { results.append(.success(result)) } }
    func queue(failure: MidgarStoreError) { lock.withLock { results.append(.failure(failure)) } }
    func setCatalog(_ products: [StoreProduct]) { lock.withLock { catalog = products } }
    func emit(_ event: MidgarStoreEvent) { continuation.yield(event) }

    func products() async throws -> [StoreProduct] { lock.withLock { catalog } }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult {
        let next = lock.withLock { () -> Result<MidgarReceiptResult, MidgarStoreError> in
            bought.append(productID)
            return results.isEmpty ? .success(.cancelled) : results.removeFirst()
        }
        return try next.get()
    }

    func events() async -> AsyncStream<MidgarStoreEvent> { stream }
}

/// Records every sleep and returns at once. `slept` is touched only inside `lock`.
final class InstantSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var slept: [Duration] = []

    var requested: [Duration] { lock.withLock { slept } }

    func sleep(_ duration: Duration) async throws {
        lock.withLock { slept.append(duration) }
    }
}

/// A clock the test moves by hand. `current` is touched only inside `lock`.
final class CreditsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = creditsEpoch

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// Collects the client's log lines. `captured` is touched only inside `lock`.
final class CreditsLogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []

    var lines: [String] { lock.withLock { captured } }

    func record(_ line: String) { lock.withLock { captured.append(line) } }
}

/// One wallet client under test with every collaborator the test may inspect.
struct CreditsHarness {
    let credits: MidgarCredits
    let gateway: CreditsGateway
    let identity: FakeCreditsIdentity
    let store: FakeCreditsStore
    let sleeper: InstantSleeper
    let clock: CreditsClock
    let logs: CreditsLogCapture
    let directory: URL

    init(
        packs: [MidgarCreditsPack] = creditsPacks,
        legacyAPIKey: (@Sendable () async -> String?)? = nil,
        gateway: CreditsGateway = CreditsGateway(),
        identity: FakeCreditsIdentity = FakeCreditsIdentity(),
        store: FakeCreditsStore = FakeCreditsStore(),
        clock: CreditsClock = CreditsClock(),
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("credits-" + UUID().uuidString, isDirectory: true),
        reconciles: Bool = false,
        startsRefreshing: Bool = false
    ) {
        let sleeper = InstantSleeper()
        let logs = CreditsLogCapture()
        self.gateway = gateway
        self.identity = identity
        self.store = store
        self.sleeper = sleeper
        self.clock = clock
        self.logs = logs
        self.directory = directory
        credits = MidgarCredits(
            configuration: MidgarCreditsConfiguration(packs: packs, directory: directory),
            http: gateway.configuration(),
            identity: identity,
            purchasing: store,
            legacyAPIKey: legacyAPIKey,
            clock: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            logger: { logs.record($0) },
            reconciles: reconciles,
            startsRefreshing: startsRefreshing
        )
    }

    var queuedFile: [PendingCredit] {
        CreditsPendingStore(directory: directory, appID: "app-test").load()
    }

    /// A second client over the same directory and gateway, as after a relaunch.
    func relaunched() -> CreditsHarness {
        CreditsHarness(gateway: gateway, identity: identity, store: store, clock: clock, directory: directory)
    }
}

/// Polls until the condition holds or five seconds pass, for work that runs on the client's own tasks.
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
