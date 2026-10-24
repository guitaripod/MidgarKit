import Foundation

#if canImport(AdServices) && !os(tvOS) && !os(watchOS)
import AdServices
#endif

/// Where the Apple Ads (AdServices) attribution token comes from. ``MidgarAdServicesTokenProvider`` is the production source; tests and previews pass their own, so no test ever calls AdServices.
public protocol MidgarAdAttributionTokenProviding: Sendable {
    /// The opaque token, or nil where AdServices has none (tvOS, watchOS).
    ///
    /// - Throws: Whatever AdServices throws: always on the Simulator, and on a device that has no attribution record yet.
    func attributionToken() throws -> String?
}

/// Reads `AAAttribution.attributionToken()`. The only place MidgarCredits touches AdServices; the framework is absent on tvOS and watchOS, where there is never a token.
public struct MidgarAdServicesTokenProvider: MidgarAdAttributionTokenProviding {
    public init() {}

    public func attributionToken() throws -> String? {
        #if canImport(AdServices) && !os(tvOS) && !os(watchOS)
        return try AAAttribution.attributionToken()
        #else
        return nil
        #endif
    }
}

/// mako's verdict on a submitted token (`POST /v1/attribution`, `status`). mako answers 200 for every one of them, so measuring ads can never fail a launch. Campaign, ad group and keyword stay on the server and are not part of this type.
public enum MidgarAdAttributionStatus: String, Sendable, Codable, CaseIterable {
    /// Apple resolved the token to a paid campaign.
    case attributed
    /// Apple resolved the token and reported no campaign: an organic install.
    case organic
    /// This install was recorded before; first-touch attribution is unchanged.
    case duplicate
    /// Apple has not propagated the record yet.
    case pending
    /// Apple will not resolve the token that was sent. A later launch captures a fresh one.
    case invalid
    /// mako could not take the submission now.
    case unavailable

    /// True when the install is resolved, so no later launch captures another token. `invalid` is not final: it also happens to a good install whose token went stale while the request stalled, and every launch captures a fresh token.
    var settlesInstall: Bool {
        switch self {
        case .attributed, .organic, .duplicate:
            return true
        case .pending, .invalid, .unavailable:
            return false
        }
    }
}

/// What one ``MidgarAdAttribution/reportIfNeeded()`` pass did.
public enum MidgarAdAttributionResult: Sendable, Equatable {
    /// mako reached a final verdict, which is remembered: no later launch does anything.
    case settled(MidgarAdAttributionStatus)
    /// An earlier launch already settled this install; nothing was captured or sent.
    case alreadySettled(MidgarAdAttributionStatus)
    /// No verdict yet (the network failed, or mako said to wait): the next launch captures a fresh token and tries again.
    case deferred
    /// The app said this is not a production launch (a debug build, a UI test, demo mode): nothing was captured or sent.
    case skipped
    /// AdServices gave no token (the Simulator, tvOS, no attribution record yet): nothing was sent, and nothing is counted against this install.
    case noToken
    /// Too many launches reached mako without a final verdict, so the install is no longer retried.
    case exhausted

    /// True only for a resolved paid install.
    public var isPaidInstall: Bool {
        switch self {
        case .settled(let status), .alreadySettled(let status):
            return status == .attributed
        case .deferred, .skipped, .noToken, .exhausted:
            return false
        }
    }

    /// A token-free description for an app's file log.
    public var logDescription: String {
        switch self {
        case .settled(let status):
            return "settled(\(status.rawValue))"
        case .alreadySettled(let status):
            return "alreadySettled(\(status.rawValue))"
        case .deferred:
            return "deferred"
        case .skipped:
            return "skipped"
        case .noToken:
            return "noToken"
        case .exhausted:
            return "exhausted"
        }
    }
}

struct AdAttributionSubmission: Sendable, Equatable {
    let status: MidgarAdAttributionStatus
    let retryAfter: TimeInterval?
}

protocol AdAttributionSubmitting: Sendable {
    func submitAttribution(token: String) async throws -> AdAttributionSubmission
}

/// What survives between launches: the verdict once there is one, and how many launches reached mako without one.
struct AdAttributionState: Codable, Sendable, Equatable {
    var settled: MidgarAdAttributionStatus?
    var launchAttempts = 0
}

/// `<directory>/attribution-<app>.json`. It lives in the app's own container, so deleting the app deletes it and a reinstall counts as a new install, as it should. The token itself is never written.
struct AdAttributionStateStore: Sendable {
    let fileURL: URL

    init(directory: URL?, appID: String) {
        let base = directory ?? CreditsPendingStore.defaultDirectory
        fileURL = base.appendingPathComponent("attribution-\(CreditsPendingStore.safeName(appID)).json")
    }

    func load() -> AdAttributionState {
        guard let data = try? Data(contentsOf: fileURL), let state = try? JSONDecoder().decode(AdAttributionState.self, from: data) else {
            return AdAttributionState()
        }
        return state
    }

    func save(_ state: AdAttributionState) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

/// Captures the AdServices attribution token and hands it to mako, which exchanges it with Apple and keeps the campaign data against the Midgar ID's partition. It ports `AICredits`' reporting and is reached through ``MidgarCredits/reportAdAttributionOnce()``.
///
/// The rules it keeps: nothing happens unless the app says this is a production launch; a token is captured at most once per pass and never stored or logged; once mako reaches a final verdict nothing is captured again; a network failure leaves the install open for the next launch; and nothing here throws into a launch path.
public actor MidgarAdAttribution {
    static let attemptsPerPass = 3
    static let maximumLaunchAttempts = 5
    static let defaultRetryDelay: TimeInterval = 5
    static let longestInPassDelay: TimeInterval = 10
    static let tokenLengths = 16...8192

    private let submitter: any AdAttributionSubmitting
    private let tokenProvider: any MidgarAdAttributionTokenProviding
    private let isProductionLaunch: @Sendable () -> Bool
    private let store: AdAttributionStateStore
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log: @Sendable (String) -> Void
    private var inFlight: Task<MidgarAdAttributionResult, Never>?

    init(
        submitter: any AdAttributionSubmitting,
        tokenProvider: any MidgarAdAttributionTokenProviding,
        isProductionLaunch: @escaping @Sendable () -> Bool,
        store: AdAttributionStateStore,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        logger: @escaping @Sendable (String) -> Void
    ) {
        self.submitter = submitter
        self.tokenProvider = tokenProvider
        self.isProductionLaunch = isProductionLaunch
        self.store = store
        self.sleep = sleep
        self.log = logger
    }

    /// Does one pass, or joins the pass already running: concurrent callers share one attempt, so a launch never sends a token twice.
    @discardableResult
    public func reportIfNeeded() async -> MidgarAdAttributionResult {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task<MidgarAdAttributionResult, Never> { await self.run() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        log("credits: ad attribution \(result.logDescription)")
        return result
    }

    private func run() async -> MidgarAdAttributionResult {
        guard isProductionLaunch() else {
            return .skipped
        }
        var state = store.load()
        if let settled = state.settled {
            return .alreadySettled(settled)
        }
        guard state.launchAttempts < Self.maximumLaunchAttempts else {
            return .exhausted
        }
        guard let token = captureToken() else {
            return .noToken
        }
        return await submit(token, state: &state)
    }

    /// The trimmed token, or nil when AdServices has none, throws, or returns something mako would refuse by shape (it checks the same length and alphabet before it asks Apple).
    private func captureToken() -> String? {
        guard let raw = try? tokenProvider.attributionToken() else {
            return nil
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.hasPlausibleShape(token) ? token : nil
    }

    static func hasPlausibleShape(_ token: String) -> Bool {
        guard tokenLengths.contains(token.utf8.count) else {
            return false
        }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_")
        return token.allSatisfy(allowed.contains)
    }

    /// Sends the token up to ``attemptsPerPass`` times while mako says to wait a few seconds. A launch counts against the ceiling only when mako was reached: being offline costs nothing, so a week without a network does not give up on the install.
    private func submit(_ token: String, state: inout AdAttributionState) async -> MidgarAdAttributionResult {
        var attempt = 0
        while attempt < Self.attemptsPerPass {
            attempt += 1
            let submission: AdAttributionSubmission
            do {
                submission = try await submitter.submitAttribution(token: token)
            } catch is CancellationError {
                return .deferred
            } catch MidgarCreditsError.offline {
                return .deferred
            } catch {
                return countLaunch(&state)
            }
            if submission.status.settlesInstall {
                state.settled = submission.status
                store.save(state)
                return .settled(submission.status)
            }
            let delay = submission.retryAfter ?? Self.defaultRetryDelay
            guard submission.status == .pending, attempt < Self.attemptsPerPass, delay <= Self.longestInPassDelay else {
                return countLaunch(&state)
            }
            do {
                try await sleep(.seconds(delay))
            } catch {
                return .deferred
            }
        }
        return countLaunch(&state)
    }

    private func countLaunch(_ state: inout AdAttributionState) -> MidgarAdAttributionResult {
        state.launchAttempts += 1
        store.save(state)
        return .deferred
    }
}
