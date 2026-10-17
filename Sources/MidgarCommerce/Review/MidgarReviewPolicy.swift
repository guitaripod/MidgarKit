import Foundation

/// Why the policy holds a review prompt back. The first reason that applies is reported.
public enum MidgarReviewHold: Sendable, Equatable {
    /// The app has not reported a positive moment in this session.
    case noPositiveMoment
    /// The app was first launched less than ``MidgarReviewPolicy/minimumDaysSinceFirstLaunch`` days ago.
    case tooSoonAfterInstall
    /// The app has not run more than ``MidgarReviewPolicy/minimumSessions`` sessions.
    case tooFewSessions
    /// The app version that is running is the one that already prompted.
    case versionAlreadyPrompted
    /// The last prompt was less than ``MidgarReviewPolicy/minimumDaysBetweenPrompts`` days ago.
    case promptedRecently
    /// A purchase failed or was refunded less than ``MidgarReviewPolicy/troubleCooldownDays`` days ago.
    case recentPurchaseTrouble
}

/// What the policy says about asking for a review right now.
public enum MidgarReviewDecision: Sendable, Equatable {
    case prompt
    case hold(MidgarReviewHold)
}

/// The one review-prompt policy of every Midgar app. It decides when the app may call StoreKit's `requestReview`; it never calls it.
///
/// The rules, all of which must hold:
/// - The app reported a positive moment this session with ``noteSuccess()``: an invoice sent, a playlist saved, a goal reached. Nothing else is a reason to ask.
/// - Not in the first 3 days after the first launch and not in the first 5 sessions.
/// - Not within 120 days of the last prompt, and not on the app version that already prompted.
/// - Not within 7 days of a purchase failure or a refund the app reported, because a customer who just lost money or time is the wrong audience.
///
/// Usage: call ``beginSession()`` once per launch, ``noteSuccess()`` at each positive moment, and when it returns true ask StoreKit and then call ``notePrompted()``. Report ``notePurchaseFailure()`` and ``noteRefund()`` where they happen. State is saved after every change, per app.
///
/// StoreKit shows its prompt at most three times in 365 days whatever the app asks, and may show nothing; ``notePrompted()`` records that the app asked, which is all the app can know.
///
/// Signals: the policy does not record `review.prompt` because the signals schema has no such event yet.
///
/// It is `@unchecked Sendable` because every read and write of its mutable state happens under one lock.
public final class MidgarReviewPolicy: @unchecked Sendable {
    public static let minimumDaysSinceFirstLaunch = 3
    public static let minimumSessions = 5
    public static let minimumDaysBetweenPrompts = 120
    public static let troubleCooldownDays = 7

    private let storage: any MidgarReviewStorage
    private let clock: @Sendable () -> Date
    private let appVersion: String
    private let lock = NSLock()
    private var state: MidgarReviewState
    private var hasPositiveMoment = false

    /// - Parameters:
    ///   - storage: Where the state lives. Defaults to a file named for `appID` in Application Support.
    ///   - appVersion: The running app version, compared with the version of the last prompt. Defaults to the main bundle's `CFBundleShortVersionString`.
    ///   - clock: The current date, injectable for tests.
    public convenience init(
        appID: String,
        appVersion: String = MidgarReviewPolicy.bundleVersion,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(storage: MidgarReviewFileStorage(appID: appID), appVersion: appVersion, clock: clock)
    }

    public init(
        storage: any MidgarReviewStorage,
        appVersion: String = MidgarReviewPolicy.bundleVersion,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.appVersion = appVersion
        self.clock = clock
        var loaded = storage.load()
        if loaded.firstLaunch == nil {
            loaded.firstLaunch = clock()
            storage.save(loaded)
        }
        state = loaded
    }

    /// The main bundle's marketing version, or an empty string outside an app.
    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Counts one session. Call it once per launch.
    public func beginSession() {
        locked {
            state.sessions += 1
            storage.save(state)
        }
    }

    /// Records a positive moment in this session and returns whether to ask for a review now.
    @discardableResult
    public func noteSuccess() -> Bool {
        locked {
            hasPositiveMoment = true
            return decision() == .prompt
        }
    }

    /// The policy's answer right now, with the reason when it holds back.
    public func evaluate() -> MidgarReviewDecision {
        locked { decision() }
    }

    public func shouldPrompt() -> Bool {
        evaluate() == .prompt
    }

    /// Records that the app asked StoreKit for a review. Call it right after `requestReview`.
    public func notePrompted() {
        locked {
            state.lastPrompt = clock()
            state.lastPromptedVersion = appVersion
            hasPositiveMoment = false
            storage.save(state)
        }
    }

    /// Records a purchase that failed. Holds prompts back for ``troubleCooldownDays``.
    public func notePurchaseFailure() {
        locked {
            state.lastPurchaseFailure = clock()
            storage.save(state)
        }
    }

    /// Records a refund. Holds prompts back for ``troubleCooldownDays``.
    public func noteRefund() {
        locked {
            state.lastRefund = clock()
            storage.save(state)
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The rules in order. Call with the lock held.
    private func decision() -> MidgarReviewDecision {
        let now = clock()
        guard hasPositiveMoment else {
            return .hold(.noPositiveMoment)
        }
        if let firstLaunch = state.firstLaunch, isWithin(Self.minimumDaysSinceFirstLaunch, since: firstLaunch, now: now) {
            return .hold(.tooSoonAfterInstall)
        }
        if state.sessions <= Self.minimumSessions {
            return .hold(.tooFewSessions)
        }
        if let version = state.lastPromptedVersion, version == appVersion {
            return .hold(.versionAlreadyPrompted)
        }
        if let lastPrompt = state.lastPrompt, isWithin(Self.minimumDaysBetweenPrompts, since: lastPrompt, now: now) {
            return .hold(.promptedRecently)
        }
        let trouble = [state.lastPurchaseFailure, state.lastRefund].compactMap { $0 }
        if trouble.contains(where: { isWithin(Self.troubleCooldownDays, since: $0, now: now) }) {
            return .hold(.recentPurchaseTrouble)
        }
        return .prompt
    }

    /// True while less than `days` full days have passed since `date`, so 2 days 23 hours is still inside a 3 day window.
    private func isWithin(_ days: Int, since date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) < TimeInterval(days) * 86_400
    }
}
