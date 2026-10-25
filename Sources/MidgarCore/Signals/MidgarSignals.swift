import Foundation

/// Anonymous product analytics for a Midgar app (D7). Events are queued, kept on disk and sent in batches to `POST /v1/signals/events`.
///
/// Nothing identifying is sent: no Midgar ID, no device id, no `Authorization` header. A body holds only the event names and the props callers pass, which are strings (cut to 64 characters), integers, doubles and booleans. The server keeps daily counts per app, event and platform.
///
/// Sending rules:
/// - A batch holds at most 50 events and 32 KB.
/// - Events are sent when 20 are queued, and every 60 seconds while any are waiting. Automatic requests are at least 10 seconds apart.
/// - The queue holds 500 events; the oldest go first when it is full. It is saved to a file in Application Support at most 5 seconds after it changes and whenever a batch leaves it or ``flush()`` runs, so unsent events survive a relaunch.
/// - Offline, a timeout or a 5xx keeps the events for the next attempt. A 429 keeps them and waits for `Retry-After` (60 seconds when it is missing, at most an hour). Any other 4xx drops the batch and logs once.
/// - A `signals` kill switch in the app's ``MidgarConfig``, or the person turning ``isEnabled`` off, turns ``record(_:props:)`` and ``send(_:)`` into no-ops and empties the queue.
///
/// ``send(_:)`` is the way to send an event: it takes a generated ``MidgarSignal``, enforces on the device how often the registry lets one install send it, and stamps the install's cohort where the registry asks for it.
///
/// The host app calls ``flush()`` when it moves to the background, because the OS may suspend it before the next timer.
public actor MidgarSignals {
    /// The ``MidgarConfig`` kill key that stops signals.
    public static let killSwitchKey = "signals"

    private struct Entry {
        let sequence: UInt64
        let event: MidgarSignalEvent
    }

    private enum Outcome {
        case delivered
        case dropped(status: Int, code: String?)
        case retryLater
        case rateLimited(retryAfter: TimeInterval)

        var allowsNextBatch: Bool {
            switch self {
            case .delivered, .dropped: return true
            case .retryLater, .rateLimited: return false
            }
        }
    }

    private let client: MidgarHTTPClient
    private let configProvider: @Sendable () -> MidgarConfig
    let store: MidgarSignalsStore
    let consent: MidgarSignalsConsent
    let installDate: @Sendable () -> Date?
    let policy: MidgarSignalsPolicy
    private let platform: String
    private let appVersion: String?
    let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let logger: @Sendable (String) -> Void
    private var queue: [Entry]
    var install: InstallState?
    var periodKeys: MidgarSignalPeriodKeys?
    var queueIsDirty = false
    var ledgerIsDirty = false
    var persistTask: Task<Void, Never>?
    /// How many times the queue or the ledger was written to disk. Tests read it to prove `send` does not write per call.
    private(set) var writeCount = 0
    private var nextSequence: UInt64
    private var flushTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var timerFireDate: Date?
    private var timerGeneration: UInt64 = 0
    private var lastAttempt: Date?
    private var blockedUntil: Date?
    private var hasLoggedDrop = false
    private var retainedObjects: [AnyObject] = []

    /// - Parameters:
    ///   - configuration: Where and as which app to send. Its token provider is ignored: signals requests never carry `Authorization`.
    ///   - config: The app's current remote config, read for the `signals` kill switch. Pass `{ store.current }` from a ``MidgarConfigStore``.
    ///   - directory: Where the queue file lives. Defaults to `<Application Support>/Midgar`.
    ///   - appVersion: Sent as `X-App-Version`. Defaults to the host bundle's `CFBundleShortVersionString`.
    ///   - logger: Receives one line when a batch is dropped. Never receives event contents.
    public init(
        configuration: MidgarHTTPConfiguration,
        config: @escaping @Sendable () -> MidgarConfig = { MidgarConfig() },
        directory: URL? = nil,
        appVersion: String? = nil,
        logger: @escaping @Sendable (String) -> Void = { MidgarLog.notice($0, category: .network) }
    ) {
        self.init(
            configuration: configuration,
            config: config,
            directory: directory,
            appVersion: appVersion ?? MidgarSignalsPlatform.bundleVersion(),
            installDate: { MidgarSignalsInstallDate.ofThisApp() },
            logger: logger,
            policy: .standard,
            platform: MidgarSignalsPlatform.current,
            now: { Date() },
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    init(
        configuration: MidgarHTTPConfiguration,
        config: @escaping @Sendable () -> MidgarConfig,
        directory: URL?,
        appVersion: String?,
        installDate: @escaping @Sendable () -> Date? = { MidgarSignalsInstallDate.ofThisApp() },
        logger: @escaping @Sendable (String) -> Void,
        policy: MidgarSignalsPolicy,
        platform: String,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        let store = MidgarSignalsStore(directory: directory, appID: configuration.appID)
        let saved = store.load()
        self.client = MidgarHTTPClient(configuration: configuration.settingTokenProvider(nil))
        self.configProvider = config
        self.store = store
        self.consent = MidgarSignalsConsent(store: store)
        self.installDate = installDate
        self.policy = policy
        self.platform = platform
        self.appVersion = appVersion
        self.now = now
        self.sleep = sleep
        self.logger = logger
        self.queue = saved.enumerated().map { Entry(sequence: UInt64($0.offset), event: $0.element) }
        self.nextSequence = UInt64(saved.count)
        if !saved.isEmpty {
            Task { await self.scheduleSavedEvents() }
        }
    }

    /// The number of events waiting to be sent.
    public var pendingCount: Int {
        queue.count
    }

    /// Queues one event as it is, with no uniqueness and no cohort. Prefer ``send(_:)``. Does nothing while the kill switch is on or ``isEnabled`` is off, and empties the queue.
    ///
    /// - Parameters:
    ///   - name: An event name from the signals schema. The server drops names it does not know.
    ///   - props: The event's props, only the ones the schema lists for that name.
    public func record(_ name: String, props: [String: MidgarSignalValue] = [:]) {
        guard !isSuppressed else {
            clearQueue()
            return
        }
        guard let event = MidgarSignalEvent(name: name, props: props) else {
            return
        }
        enqueue(event)
    }

    /// Appends an event that passed every check. The queue file follows within ``MidgarSignalsPolicy/persistInterval`` seconds, not on every call.
    func enqueue(_ event: MidgarSignalEvent) {
        queue.append(Entry(sequence: nextSequence, event: event))
        nextSequence += 1
        if queue.count > policy.maximumQueued {
            queue.removeFirst(queue.count - policy.maximumQueued)
        }
        queueIsDirty = true
        schedulePersist()
        if queue.count >= policy.flushThreshold {
            beginFlush(explicit: false)
        }
        scheduleTimer(after: policy.flushInterval)
    }

    /// Sends everything queued now, batch after batch, and returns when the queue is empty or a batch could not be sent. Call it when the app moves to the background. It ignores the 10 second spacing of automatic requests but still waits out a `Retry-After`. It also writes the queue and the uniqueness ledger to disk.
    public func flush() async {
        persistPending()
        while let running = flushTask {
            await running.value
        }
        if let task = beginFlush(explicit: true) {
            await task.value
        }
    }

    /// Keeps an object alive for the life of the instance, such as the MetricKit subscriber.
    func retain(_ object: AnyObject) {
        retainedObjects.append(object)
    }

    /// Waits for the flush in flight, if any. Tests use it to observe the end of a threshold or timer flush.
    func waitForIdle() async {
        while let running = flushTask {
            await running.value
        }
    }

    var isKilled: Bool {
        configProvider().isKilled(Self.killSwitchKey)
    }

    /// True while nothing may be recorded: the remote kill switch is on or the person turned usage counts off.
    var isSuppressed: Bool {
        !consent.isEnabled || isKilled
    }

    func clearQueue() {
        guard !queue.isEmpty else {
            return
        }
        queue.removeAll()
        persistQueueNow()
    }

    /// Empties the queue and removes its file, even when the queue in memory is already empty and only an earlier run left the file.
    func discardQueue() {
        queue.removeAll()
        persistQueueNow()
    }

    /// Writes the queue at once, and the ledger too if it changed, so a relaunch never finds a sent event still queued or a queued one forgotten.
    private func persistQueueNow() {
        queueIsDirty = true
        persistPending()
    }

    /// Arms the one write that follows a change, unless one is already armed. The task holds the actor weakly, so an instance that goes away takes its pending write with it.
    func schedulePersist() {
        guard persistTask == nil else {
            return
        }
        let delay = policy.persistInterval
        persistTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else {
                return
            }
            await self?.persistPending()
        }
    }

    /// Writes whatever changed since the last write: the queue file, and the ledger with the entries of passed periods pruned.
    func persistPending() {
        persistTask?.cancel()
        persistTask = nil
        if queueIsDirty {
            queueIsDirty = false
            writeCount += 1
            store.save(queue.map(\.event))
        }
        if ledgerIsDirty, install != nil {
            ledgerIsDirty = false
            writeCount += 1
            install?.ledger.prune(keeping: currentPeriodKeys(at: now()))
            if let state = install {
                state.ledgerStore.save(state.ledger)
            }
        }
    }

    private func scheduleSavedEvents() {
        scheduleTimer(after: policy.flushInterval)
    }

    /// Starts a flush task when one may run now: not killed, nothing in flight, events waiting, and the spacing and `Retry-After` waits over. Otherwise schedules the timer for the end of the wait.
    @discardableResult
    private func beginFlush(explicit: Bool) -> Task<Void, Never>? {
        if isSuppressed {
            clearQueue()
            return nil
        }
        guard flushTask == nil, !queue.isEmpty else {
            return nil
        }
        let wait = waitBeforeSending(explicit: explicit)
        if wait > 0 {
            scheduleTimer(after: wait)
            return nil
        }
        let task = Task { await self.performFlush(drainAll: explicit) }
        flushTask = task
        return task
    }

    /// Seconds until a request may go out: the rest of a `Retry-After`, and for automatic requests the rest of the spacing.
    private func waitBeforeSending(explicit: Bool) -> TimeInterval {
        let current = now()
        var wait: TimeInterval = 0
        if let blockedUntil {
            wait = max(wait, blockedUntil.timeIntervalSince(current))
        }
        if !explicit, let lastAttempt {
            wait = max(wait, policy.minimumSpacing - current.timeIntervalSince(lastAttempt))
        }
        return wait
    }

    /// Arms the timer unless one is already due sooner.
    private func scheduleTimer(after delay: TimeInterval) {
        let fireDate = now().addingTimeInterval(delay)
        if timer != nil, let existing = timerFireDate, existing <= fireDate {
            return
        }
        timer?.cancel()
        timerGeneration += 1
        let generation = timerGeneration
        timerFireDate = fireDate
        let sleep = sleep
        timer = Task {
            do {
                try await sleep(.seconds(delay))
            } catch {
                return
            }
            self.timerFired(generation)
        }
    }

    private func timerFired(_ generation: UInt64) {
        guard generation == timerGeneration else {
            return
        }
        timer = nil
        timerFireDate = nil
        beginFlush(explicit: false)
    }

    private func performFlush(drainAll: Bool) async {
        var outcome = Outcome.delivered
        repeat {
            if isSuppressed {
                clearQueue()
                break
            }
            guard let batch = nextBatch() else {
                break
            }
            lastAttempt = now()
            outcome = await deliver(batch)
            settle(batch, outcome)
        } while drainAll && outcome.allowsNextBatch && !queue.isEmpty
        flushTask = nil
        scheduleFollowUp(after: outcome)
    }

    /// The oldest events that fit one request: at most the event limit and the byte limit. An event too large to ever fit is dropped here.
    private func nextBatch() -> [Entry]? {
        var batch: [Entry] = []
        var bytes = Self.bodyOverhead
        var oversized: Set<UInt64> = []
        for entry in queue {
            let size = Self.encodedSize(of: entry.event)
            if size + Self.bodyOverhead > policy.maximumBatchBytes {
                oversized.insert(entry.sequence)
                continue
            }
            let separator = batch.isEmpty ? 0 : 1
            guard batch.count < policy.maximumBatchEvents, bytes + separator + size <= policy.maximumBatchBytes else {
                break
            }
            batch.append(entry)
            bytes += separator + size
        }
        if !oversized.isEmpty {
            queue.removeAll { oversized.contains($0.sequence) }
            persistQueueNow()
        }
        return batch.isEmpty ? nil : batch
    }

    /// `{"events":[` and `]}` around the comma-joined events.
    private static let bodyOverhead = 13

    private static func encodedSize(of event: MidgarSignalEvent) -> Int {
        (try? JSONEncoder().encode(event).count) ?? Int.max / 2
    }

    private func deliver(_ batch: [Entry]) async -> Outcome {
        var headers = ["X-Platform": platform]
        if let appVersion, !appVersion.isEmpty {
            headers["X-App-Version"] = appVersion
        }
        let request = MidgarRequest(
            service: "signals",
            path: "events",
            method: .post,
            headers: headers,
            body: MidgarSignalBatch(events: batch.map(\.event)),
            neverRetries: true
        )
        do {
            _ = try await client.sendRaw(request)
            return .delivered
        } catch {
            return outcome(for: error)
        }
    }

    /// Offline, timeouts and server errors keep the events, a 429 keeps them and waits, and every other refusal means the batch can never be accepted.
    private func outcome(for error: MidgarHTTPError) -> Outcome {
        switch error {
        case .rateLimited(let retryAfter, _):
            return .rateLimited(retryAfter: min(retryAfter ?? policy.defaultRetryAfter, policy.maximumRetryAfter))
        case .offline, .timeout, .cancelled, .tokenUnavailable, .decoding:
            return .retryLater
        case .server(let status, let code, _):
            return (400..<500).contains(status) ? .dropped(status: status, code: code) : .retryLater
        case .unauthorized(let code):
            return .dropped(status: 401, code: code)
        case .paymentRequired(let code):
            return .dropped(status: 402, code: code)
        case .notFound(let code):
            return .dropped(status: 404, code: code)
        case .invalidRequest:
            return .dropped(status: 0, code: nil)
        }
    }

    /// Removes a delivered or refused batch from the queue, or starts the `Retry-After` wait.
    private func settle(_ batch: [Entry], _ outcome: Outcome) {
        switch outcome {
        case .delivered:
            remove(batch)
        case .dropped(let status, let code):
            remove(batch)
            logDropOnce(count: batch.count, status: status, code: code)
        case .rateLimited(let retryAfter):
            blockedUntil = now().addingTimeInterval(retryAfter)
        case .retryLater:
            break
        }
    }

    private func remove(_ batch: [Entry]) {
        let sent = Set(batch.map(\.sequence))
        queue.removeAll { sent.contains($0.sequence) }
        persistQueueNow()
    }

    private func logDropOnce(count: Int, status: Int, code: String?) {
        guard !hasLoggedDrop else {
            return
        }
        hasLoggedDrop = true
        logger("signals dropped \(count) events after HTTP \(status) \(code ?? "-"); later refusals are not logged")
    }

    /// Arms the timer for whatever is still queued: the `Retry-After` wait after a 429, the spacing while a full batch is waiting, otherwise the regular interval.
    private func scheduleFollowUp(after outcome: Outcome) {
        guard !queue.isEmpty else {
            return
        }
        switch outcome {
        case .rateLimited(let retryAfter):
            scheduleTimer(after: retryAfter)
        case .delivered, .dropped:
            scheduleTimer(after: queue.count >= policy.flushThreshold ? policy.minimumSpacing : policy.flushInterval)
        case .retryLater:
            scheduleTimer(after: policy.flushInterval)
        }
    }
}
