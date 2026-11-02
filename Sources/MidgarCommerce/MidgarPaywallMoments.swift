import Foundation
import MidgarCore

/// The two commerce moments the rest of an app reacts to: a paywall came on screen, and the customer bought something.
///
/// They are posted on a `NotificationCenter` so every ``MidgarReviewPolicy`` in the process hears them without wiring: a
/// review prompt waits out a session in which a paywall went unanswered, and a purchase makes the customer a payer. The
/// app reports a paywall with ``noteShown(placement:)``; ``MidgarStore`` posts a purchase itself.
public enum MidgarPaywallMoments {
    /// Posted each time a paywall comes on screen.
    public static let shown = Notification.Name("cc.midgarcorp.commerce.paywall-shown")
    /// Posted after the customer bought a product in this app and the store verified and finished it. Ask to Buy approvals, renewals and purchases from other devices are not posted.
    public static let purchased = Notification.Name("cc.midgarcorp.commerce.purchased")

    /// Records that a paywall is on screen: sends `paywall.view` with `placement` and tells the review policy. Call it once each time a paywall appears.
    ///
    /// Placements: `moment` for an offer the app made at a value moment, `feature` or `limit` for a locked feature or a used-up allowance the person ran into, `settings` for one opened from Settings, `onboarding` and `launch` for the first run.
    public static func noteShown(placement: MidgarSignal.Placement, center: NotificationCenter = .default) {
        Task { await MidgarSignals.shared?.send(.paywallView(placement: placement)) }
        center.post(name: shown, object: nil)
    }
}

/// Whether a paywall went unanswered in this session: one came on screen and no purchase followed. An app that keeps its
/// own review rules instead of ``MidgarReviewPolicy`` holds its prompt back while this is true. Keep one for the life of
/// the process; a new process starts answered.
///
/// It is `@unchecked Sendable` because the flag is only read and written under its lock.
public final class MidgarPaywallSession: @unchecked Sendable {
    private let center: NotificationCenter
    private let lock = NSLock()
    private var unanswered = false
    private var observers: [any NSObjectProtocol] = []

    public init(center: NotificationCenter = .default) {
        self.center = center
        let shown = center.addObserver(forName: MidgarPaywallMoments.shown, object: nil, queue: nil) { [weak self] _ in
            self?.set(unanswered: true)
        }
        let purchased = center.addObserver(forName: MidgarPaywallMoments.purchased, object: nil, queue: nil) { [weak self] _ in
            self?.set(unanswered: false)
        }
        observers = [shown, purchased]
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    /// True after a paywall came on screen in this session with no purchase since.
    public var isUnanswered: Bool {
        lock.withLock { unanswered }
    }

    private func set(unanswered value: Bool) {
        lock.withLock { unanswered = value }
    }
}
