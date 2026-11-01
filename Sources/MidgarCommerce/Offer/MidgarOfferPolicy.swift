import Foundation

/// Why the policy holds an offer back. The first reason that applies is reported.
public enum MidgarOfferHold: Sendable, Equatable {
    /// The person already owns what the offer sells.
    case alreadyOwned
    /// The app has offered ``MidgarOfferPolicy/maximumOffers`` times on its own; from here on only the person opens the paywall.
    case offersUsedUp
    /// The app already offered in this session.
    case offeredThisSession
    /// Not enough value moments yet: the first offer waits for ``MidgarOfferPolicy/firstOfferAfter``, each later one for ``MidgarOfferPolicy/laterOfferEvery`` more.
    case notEnoughValueYet
    /// The last offer was less than ``MidgarOfferPolicy/minimumDaysBetweenOffers`` days ago.
    case offeredRecently
}

/// What the policy says about offering the paywall right now.
public enum MidgarOfferDecision: Sendable, Equatable {
    case offer
    case hold(MidgarOfferHold)
}

/// The one rule for when a Midgar app offers its paywall without being asked: right after the person got something
/// they came for, never before, and never as a nag (decision D22, which removed the free trials).
///
/// The rules, all of which must hold:
/// - The person does not own the offer yet (the app passes that to ``noteValue(isOwned:)``, or reports ``noteOwned()``).
/// - The app reported ``firstOfferAfter`` value moments before the first offer: a finished lesson, a saved playlist, a
///   first invoice. Each later offer waits for ``laterOfferEvery`` more value moments and ``minimumDaysBetweenOffers`` days.
/// - At most one offer per session, and at most ``maximumOffers`` in all. A paywall the person opens themselves, from a
///   locked feature or Settings, is not an offer and is not counted.
///
/// Usage: call ``noteValue(isOwned:)`` at each value moment; when it returns true, present the paywall and call
/// ``noteOffered()``. Call ``noteOwned()`` after a purchase or restore. State is saved after every change, per app.
///
/// It is `@unchecked Sendable` because every read and write of its mutable state happens under one lock.
public final class MidgarOfferPolicy: @unchecked Sendable {
    public static let maximumOffers = 3
    public static let minimumDaysBetweenOffers = 3

    /// Value moments before the first offer.
    public let firstOfferAfter: Int
    /// Value moments after an offer before the next one.
    public let laterOfferEvery: Int

    private let storage: any MidgarOfferStorage
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state: MidgarOfferState
    private var offeredThisSession = false

    /// - Parameters:
    ///   - storage: Where the state lives. Defaults to a file named for `appID` in Application Support.
    ///   - firstOfferAfter: Value moments before the first offer; 1 offers right after the first one.
    ///   - laterOfferEvery: Value moments between later offers.
    ///   - clock: The current date, injectable for tests.
    public convenience init(
        appID: String,
        firstOfferAfter: Int = 1,
        laterOfferEvery: Int = 3,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            storage: MidgarOfferFileStorage(appID: appID), firstOfferAfter: firstOfferAfter,
            laterOfferEvery: laterOfferEvery, clock: clock)
    }

    public init(
        storage: any MidgarOfferStorage,
        firstOfferAfter: Int = 1,
        laterOfferEvery: Int = 3,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.firstOfferAfter = max(1, firstOfferAfter)
        self.laterOfferEvery = max(1, laterOfferEvery)
        self.clock = clock
        state = storage.load()
    }

    /// Records a value moment and returns whether to offer the paywall now.
    @discardableResult
    public func noteValue(isOwned: Bool) -> Bool {
        locked {
            state.valueMoments += 1
            if isOwned {
                state.owned = true
            }
            storage.save(state)
            return decision() == .offer
        }
    }

    /// The policy's answer right now, with the reason when it holds back.
    public func evaluate() -> MidgarOfferDecision {
        locked { decision() }
    }

    /// Records that the app offered the paywall. Call it when the paywall is on screen.
    public func noteOffered() {
        locked {
            state.offers += 1
            state.lastOffer = clock()
            state.valueMomentsAtLastOffer = state.valueMoments
            offeredThisSession = true
            storage.save(state)
        }
    }

    /// Records that the person owns the offer, after a purchase or a restore. No offer follows.
    public func noteOwned() {
        locked {
            state.owned = true
            storage.save(state)
        }
    }

    /// How many offers the app made so far.
    public var offers: Int {
        locked { state.offers }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The rules in order. Call with the lock held.
    private func decision() -> MidgarOfferDecision {
        if state.owned {
            return .hold(.alreadyOwned)
        }
        if state.offers >= Self.maximumOffers {
            return .hold(.offersUsedUp)
        }
        if offeredThisSession {
            return .hold(.offeredThisSession)
        }
        guard let lastOffer = state.lastOffer else {
            return state.valueMoments >= firstOfferAfter ? .offer : .hold(.notEnoughValueYet)
        }
        if state.valueMoments - state.valueMomentsAtLastOffer < laterOfferEvery {
            return .hold(.notEnoughValueYet)
        }
        if clock().timeIntervalSince(lastOffer) < TimeInterval(Self.minimumDaysBetweenOffers) * 86_400 {
            return .hold(.offeredRecently)
        }
        return .offer
    }
}
