import Foundation
import Testing
@testable import MidgarCore

/// A clock the test moves by hand.
final class SignalsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

/// Stands in for `Task.sleep`: records each requested duration and suspends until the test fires the timers or the timer task is cancelled.
actor TimerGate {
    private(set) var durations: [TimeInterval] = []
    private var waiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextID = 0

    func sleep(_ duration: Duration) async throws {
        durations.append(duration.timeInterval)
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func fireAll() {
        let current = waiters
        waiters.removeAll()
        for continuation in current.values {
            continuation.resume()
        }
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

final class SignalsLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.withLock { recorded }
    }

    func record(_ line: String) {
        lock.withLock { recorded.append(line) }
    }
}

final class ConfigBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = MidgarConfig()

    var value: MidgarConfig {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// A snapshot whose document kills the `signals` feature.
func killedSignalsConfig() throws -> MidgarConfig {
    let json = #"{"app":"dream-eater","version":9,"kill":{"signals":true}}"#
    let document = try JSONDecoder().decode(MidgarConfigDocument.self, from: Data(json.utf8))
    return MidgarConfig(document: document, defaults: [:])
}

/// One test's worth of signals plumbing: a stub host, a directory for the queue file, a manual clock and timer gate.
final class SignalsHarness: @unchecked Sendable {
    let host = HTTPTestHost()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString)", isDirectory: true)
    let clock = SignalsTestClock()
    let gate = TimerGate()
    let logs = SignalsLogRecorder()
    let config = ConfigBox()
    let appID = "dream-eater"

    func makeSignals(
        platform: String = "ios",
        appVersion: String? = "2.1",
        installDate: @escaping @Sendable () -> Date? = { nil },
        policy: MidgarSignalsPolicy = .standard,
        tokenProvider: (@Sendable () async throws -> String?)? = nil
    ) -> MidgarSignals {
        let configuration = MidgarHTTPConfiguration(
            baseURL: host.baseURL,
            appID: appID,
            session: makeStubSession(),
            tokenProvider: tokenProvider,
            userAgent: "TestApp/1.0 MidgarKit/4.0.0",
            timeout: 5
        )
        let config = config
        let logs = logs
        let clock = clock
        let gate = gate
        return MidgarSignals(
            configuration: configuration,
            config: { config.value },
            directory: directory,
            appVersion: appVersion,
            installDate: installDate,
            logger: { logs.record($0) },
            policy: policy,
            platform: platform,
            now: { clock.now },
            sleep: { try await gate.sleep($0) }
        )
    }

    /// Writes events to the queue file the way a previous run would have left them.
    func seed(_ events: [(name: String, props: [String: MidgarSignalValue])]) {
        let store = MidgarSignalsStore(directory: directory, appID: appID)
        store.save(events.compactMap { MidgarSignalEvent(name: $0.name, props: $0.props) })
    }

    var ledgerFile: URL {
        MidgarSignalsLedgerStore(store: MidgarSignalsStore(directory: directory, appID: appID)).fileURL
    }

    var ledgerFileExists: Bool {
        FileManager.default.fileExists(atPath: ledgerFile.path)
    }

    /// The marks the ledger file holds, or none when there is no file.
    var ledgerOnDisk: [String: String] {
        guard let data = try? Data(contentsOf: ledgerFile) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    var storedCohort: String? {
        MidgarSignalsCohortStore(store: MidgarSignalsStore(directory: directory, appID: appID)).load()
    }

    /// Moves the clock to one hour after the start of the current day, week or month of the device's calendar, so a later advance of hours stays inside that period and an advance of days or more leaves it.
    func align(to component: Calendar.Component) {
        let calendar = MidgarSignals.activityCalendar
        guard let start = calendar.dateInterval(of: component, for: clock.now)?.start else { return }
        clock.advance(by: start.timeIntervalSince(clock.now) + 3_600)
    }

    /// Moves the clock to one hour into the next day, week or month.
    func advance(toNext component: Calendar.Component) {
        let calendar = MidgarSignals.activityCalendar
        guard let end = calendar.dateInterval(of: component, for: clock.now)?.end else { return }
        clock.advance(by: end.timeIntervalSince(clock.now) + 3_600)
    }

    /// Sends what is queued and returns the names and props of what the host received since the last call.
    func drain(_ signals: MidgarSignals) async -> [(name: String, props: [String: Any])] {
        let before = host.requests.count
        host.enqueue([acceptedReply])
        await signals.flush()
        return host.requests.dropFirst(before).flatMap(Self.events(in:)).map {
            (name: $0["name"] as? String ?? "", props: $0["props"] as? [String: Any] ?? [:])
        }
    }

    var queueFileExists: Bool {
        FileManager.default.fileExists(atPath: MidgarSignalsStore(directory: directory, appID: appID).fileURL.path)
    }

    /// The decoded events of each request the host received, in order.
    var sentBatches: [[[String: Any]]] {
        host.requests.map(Self.events(in:))
    }

    static func events(in request: CapturedRequest) -> [[String: Any]] {
        guard let body = request.body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return []
        }
        return object["events"] as? [[String: Any]] ?? []
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

let acceptedReply = StubReply.json(202, #"{"accepted":1,"dropped":0}"#)

/// Polls until the condition holds, for work that happens on a timer task the test cannot await.
func eventually(timeout: TimeInterval = 5, _ condition: @Sendable () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

/// Records `count` events named `tap`, each with its index in `n`.
func recordTaps(_ signals: MidgarSignals, _ range: Range<Int>) async {
    for index in range {
        await signals.record("tap", props: ["n": .int(index)])
    }
}

extension MidgarSignalsPolicy {
    /// The standard thresholds with another write delay.
    func persisting(after interval: TimeInterval) -> MidgarSignalsPolicy {
        MidgarSignalsPolicy(
            flushThreshold: flushThreshold,
            flushInterval: flushInterval,
            minimumSpacing: minimumSpacing,
            maximumBatchEvents: maximumBatchEvents,
            maximumBatchBytes: maximumBatchBytes,
            maximumQueued: maximumQueued,
            defaultRetryAfter: defaultRetryAfter,
            maximumRetryAfter: maximumRetryAfter,
            persistInterval: interval
        )
    }
}
