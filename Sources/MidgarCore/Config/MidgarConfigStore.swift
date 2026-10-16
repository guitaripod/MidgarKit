import Foundation

/// What a call to ``MidgarConfigStore/refresh(force:)`` did.
public enum MidgarConfigRefreshResult: Sendable, Equatable {
    case updated(version: Int)
    case unchanged
    case noConfig
    case rejected(MidgarConfigError)
    case failed(MidgarHTTPError)
    case throttled
}

/// Fetches, verifies and keeps an app's signed remote config.
///
/// ``current`` is a nonisolated, always-available snapshot: it is the verified last-good document from disk right after `init`, and compiled defaults when there is none, so launch code never awaits. ``refresh(force:)`` updates it; ``updates()`` reports every change.
///
/// Rules, in order:
/// - A document that fails verification, names another app, or has a `version` below the highest one accepted is rejected, logged without the JWS, and the current snapshot stays. An equal version is a no-op.
/// - 304 keeps the current snapshot. Offline, timeouts and any other HTTP error keep it too.
/// - 404 means nothing is published for the app. The last good document, its cache file and the anti-rollback floor all stay, so a misrouted 404 never lifts a kill switch. An app with no document keeps its compiled defaults.
public actor MidgarConfigStore {
    /// The default gap between network refreshes, 15 minutes.
    public static let defaultMinimumRefreshInterval: TimeInterval = 15 * 60

    private struct Envelope: Decodable, Sendable {
        let config: String
    }

    private let slug: String
    private let client: MidgarHTTPClient
    private let defaults: [String: MidgarConfigValue]
    private let verifier: MidgarConfigVerifier
    private let cache: MidgarConfigCache
    private let minimumRefreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let logger: @Sendable (String) -> Void
    private let box: MidgarConfigStateBox
    private var activeDocument: MidgarConfigDocument?
    private var floorVersion: Int
    private var lastAnswer: Date?
    private var inFlight: Task<MidgarConfigRefreshResult, Never>?

    /// - Parameters:
    ///   - slug: The registry slug. Documents for any other app are rejected.
    ///   - client: Sends `GET /v1/config/<slug>`.
    ///   - defaults: The app's compiled defaults, used for every key a document lacks.
    ///   - keys: The pinned public keys. Tests inject their own.
    ///   - cacheDirectory: Where `config-<slug>.jws` lives. Defaults to `<Application Support>/Midgar`.
    ///   - minimumRefreshInterval: Seconds between network refreshes unless forced.
    ///   - now: The clock, injectable for tests.
    ///   - logger: Receives one line per rejection or fallback. Never receives a JWS.
    public init(
        slug: String,
        client: MidgarHTTPClient,
        defaults: [String: MidgarConfigValue] = [:],
        keys: [MidgarConfigKey] = MidgarConfigKey.pinned,
        cacheDirectory: URL? = nil,
        minimumRefreshInterval: TimeInterval = MidgarConfigStore.defaultMinimumRefreshInterval,
        now: @escaping @Sendable () -> Date = { Date() },
        logger: @escaping @Sendable (String) -> Void = { MidgarLog.notice($0, category: .config) }
    ) {
        let verifier = MidgarConfigVerifier(keys: keys, slug: slug)
        let cache = MidgarConfigCache(directory: cacheDirectory, slug: slug)
        let cached = Self.loadCached(cache: cache, verifier: verifier, logger: logger)
        self.slug = slug
        self.client = client
        self.defaults = defaults
        self.verifier = verifier
        self.cache = cache
        self.minimumRefreshInterval = minimumRefreshInterval
        self.now = now
        self.logger = logger
        self.activeDocument = cached
        self.floorVersion = cached?.version ?? 0
        self.box = MidgarConfigStateBox(Self.snapshot(of: cached, defaults: defaults))
    }

    /// The snapshot to read right now. Safe from any thread and any actor, never suspends.
    public nonisolated var current: MidgarConfig {
        box.current
    }

    /// A stream of snapshots, one per change, starting after the call. It keeps only the newest unread snapshot.
    public nonisolated func updates() -> AsyncStream<MidgarConfig> {
        box.subscribe()
    }

    /// Fetches the document and applies it under the rules in the type documentation.
    ///
    /// Without `force`, a call within `minimumRefreshInterval` of the last answer from the server returns `.throttled` without a request. Transport failures do not start the interval, so a device that was offline retries as soon as it is asked to. Concurrent calls share one request.
    public func refresh(force: Bool = false) async -> MidgarConfigRefreshResult {
        if let inFlight {
            return await inFlight.value
        }
        if !force, isWithinMinimumInterval() {
            return .throttled
        }
        let task = Task { await self.fetchAndApply() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func isWithinMinimumInterval() -> Bool {
        guard let lastAnswer else {
            return false
        }
        return now().timeIntervalSince(lastAnswer) < minimumRefreshInterval
    }

    private func fetchAndApply() async -> MidgarConfigRefreshResult {
        do throws(MidgarHTTPError) {
            let envelope: Envelope = try await client.send(request())
            lastAnswer = now()
            return apply(envelope.config)
        } catch {
            return handle(error)
        }
    }

    private func request() -> MidgarRequest {
        var headers: [String: String] = [:]
        if let activeDocument {
            headers["If-None-Match"] = "\"\(activeDocument.version)\""
        }
        return MidgarRequest(service: "config", path: slug, headers: headers)
    }

    private func handle(_ error: MidgarHTTPError) -> MidgarConfigRefreshResult {
        switch error {
        case .server(status: 304, _, _):
            lastAnswer = now()
            return .unchanged
        case .notFound:
            lastAnswer = now()
            return noConfigPublished()
        default:
            logger("config \(slug) refresh failed: \(error.logName)")
            return .failed(error)
        }
    }

    private func apply(_ jws: String) -> MidgarConfigRefreshResult {
        let document: MidgarConfigDocument
        do throws(MidgarConfigError) {
            document = try verifier.verify(jws)
            try checkNotRolledBack(document)
        } catch {
            logger("config \(slug) rejected: \(error.logName)")
            return .rejected(error)
        }
        if document.version == activeDocument?.version {
            return .unchanged
        }
        activeDocument = document
        floorVersion = document.version
        if !cache.write(jws) {
            logger("config \(slug) cache write failed")
        }
        box.publish(MidgarConfig(document: document, defaults: defaults))
        return .updated(version: document.version)
    }

    private func checkNotRolledBack(_ document: MidgarConfigDocument) throws(MidgarConfigError) {
        if document.version < floorVersion {
            throw .rolledBack(version: document.version, lastGood: floorVersion)
        }
    }

    /// 404 says nothing is published. The last good document stays active, so a misrouted 404 cannot lift a kill switch; config changes only by publishing a newer document.
    private func noConfigPublished() -> MidgarConfigRefreshResult {
        logger("config \(slug) not published, keeping \(activeDocument == nil ? "compiled defaults" : "the last good document")")
        return .noConfig
    }

    private static func snapshot(of document: MidgarConfigDocument?, defaults: [String: MidgarConfigValue]) -> MidgarConfig {
        document.map { MidgarConfig(document: $0, defaults: defaults) } ?? MidgarConfig(defaults: defaults)
    }

    /// The cached document, or nil when the file is missing, tampered with, signed by another key or for another app.
    private static func loadCached(
        cache: MidgarConfigCache,
        verifier: MidgarConfigVerifier,
        logger: @Sendable (String) -> Void
    ) -> MidgarConfigDocument? {
        guard let jws = cache.read() else {
            return nil
        }
        do {
            return try verifier.verify(jws)
        } catch {
            logger("config \(verifier.slug) cache ignored: \(error.logName)")
            return nil
        }
    }
}
