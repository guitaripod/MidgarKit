import Foundation

/// Why the policy holds a review prompt back. The first reason that applies is reported.
public enum MidgarReviewHold: Sendable, Equatable {
    /// The app has not reported a positive moment in this session.
    case noPositiveMoment
    /// A paywall came on screen in this session and no purchase followed: someone who just said no to paying is the wrong audience.
    case paywallUnanswered
    /// The app was first launched less than the policy's ``MidgarReviewFloors/daysSinceFirstLaunch`` days ago.
    case tooSoonAfterInstall
    /// The app has not run more than the policy's ``MidgarReviewFloors/sessions`` sessions.
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

/// How long a customer who has not bought anything must have used the app before the first ask. A purchase waives both.
public struct MidgarReviewFloors: Sendable, Equatable {
    /// Full days since the first launch that must have passed.
    public var daysSinceFirstLaunch: Int
    /// Sessions the app must have run more than.
    public var sessions: Int

    public init(daysSinceFirstLaunch: Int, sessions: Int) {
        self.daysSinceFirstLaunch = daysSinceFirstLaunch
        self.sessions = sessions
    }

    /// Three days and more than five sessions, for apps whose good moments come several times a day.
    public static let standard = MidgarReviewFloors(
        daysSinceFirstLaunch: MidgarReviewPolicy.minimumDaysSinceFirstLaunch,
        sessions: MidgarReviewPolicy.minimumSessions
    )
}

/// The one review-prompt policy of every Midgar app. It decides when the app may call StoreKit's `requestReview`; it never calls it.
///
/// The rules, all of which must hold:
/// - The app reported a positive moment this session with ``noteSuccess()``: an invoice sent, a playlist saved, a goal reached. Nothing else is a reason to ask. After a purchase, only a moment that follows it counts, so a buyer is asked once they have used what they bought.
/// - No paywall went unanswered this session: one came on screen (``MidgarPaywallMoments/noteShown(placement:)``) and no purchase followed.
/// - Past the policy's ``MidgarReviewFloors``, by default not in the first 3 days after the first launch and not in the first 5 sessions, unless the customer bought something: a payer has already shown they value the app.
/// - Not within 120 days of the last prompt, and not on the app version that already prompted.
/// - Not within 7 days of a purchase failure or a refund the app reported, because a customer who just lost money or time is the wrong audience.
///
/// Usage: call ``beginSession()`` once per launch, ``noteSuccess()`` at each positive moment, and when it returns true ask StoreKit and then call ``notePrompted()``. Report ``notePurchaseFailure()`` and ``noteRefund()`` where they happen. Paywalls and purchases arrive by themselves through ``MidgarPaywallMoments`` on the notification center the policy was given. State is saved after every change, per app.
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

    /// The install-age and session floors this policy holds a non-payer to.
    public let floors: MidgarReviewFloors

    private let storage: any MidgarReviewStorage
    private let clock: @Sendable () -> Date
    private let appVersion: String
    private let lock = NSLock()
    private var state: MidgarReviewState
    private var hasPositiveMoment = false
    private var paywallUnanswered = false
    private var observers: [any NSObjectProtocol] = []
    private let center: NotificationCenter

    /// - Parameters:
    ///   - storage: Where the state lives. Defaults to a file named for `appID` in Application Support.
    ///   - appVersion: The running app version, compared with the version of the last prompt. Defaults to the main bundle's `CFBundleShortVersionString`.
    ///   - clock: The current date, injectable for tests.
    ///   - center: Where ``MidgarPaywallMoments`` are heard. Tests pass their own.
    ///   - floors: How long a non-payer must have used the app before the first ask. Defaults to ``MidgarReviewFloors/standard``.
    public convenience init(
        appID: String,
        appVersion: String = MidgarReviewPolicy.bundleVersion,
        clock: @escaping @Sendable () -> Date = { Date() },
        center: NotificationCenter = .default,
        floors: MidgarReviewFloors = .standard
    ) {
        self.init(
            storage: MidgarReviewFileStorage(appID: appID), appVersion: appVersion, clock: clock, center: center,
            floors: floors)
    }

    public init(
        storage: any MidgarReviewStorage,
        appVersion: String = MidgarReviewPolicy.bundleVersion,
        clock: @escaping @Sendable () -> Date = { Date() },
        center: NotificationCenter = .default,
        floors: MidgarReviewFloors = .standard
    ) {
        self.floors = floors
        self.storage = storage
        self.appVersion = appVersion
        self.clock = clock
        self.center = center
        var loaded = storage.load()
        if loaded.firstLaunch == nil {
            loaded.firstLaunch = clock()
            storage.save(loaded)
        }
        state = loaded
        observeCommerce()
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
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

    /// Records that a paywall came on screen. Prompts wait for the rest of the session unless a purchase follows. ``MidgarPaywallMoments/noteShown(placement:)`` calls it through the notification center.
    public func notePaywallShown() {
        locked {
            paywallUnanswered = true
        }
    }

    /// Records a purchase: the customer is a payer from now on, the paywall is answered, and only a positive moment after this one counts. ``MidgarStore`` calls it through the notification center.
    public func notePurchase() {
        locked {
            paywallUnanswered = false
            hasPositiveMoment = false
            state.lastPurchase = clock()
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

    /// Hears ``MidgarPaywallMoments`` on the policy's notification center for as long as the policy lives.
    private func observeCommerce() {
        let shown = center.addObserver(forName: MidgarPaywallMoments.shown, object: nil, queue: nil) { [weak self] _ in
            self?.notePaywallShown()
        }
        let purchased = center.addObserver(forName: MidgarPaywallMoments.purchased, object: nil, queue: nil) { [weak self] _ in
            self?.notePurchase()
        }
        observers = [shown, purchased]
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
        if paywallUnanswered {
            return .hold(.paywallUnanswered)
        }
        let isPayer = state.lastPurchase != nil
        if !isPayer, let firstLaunch = state.firstLaunch, isWithin(floors.daysSinceFirstLaunch, since: firstLaunch, now: now) {
            return .hold(.tooSoonAfterInstall)
        }
        if !isPayer, state.sessions <= floors.sessions {
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
