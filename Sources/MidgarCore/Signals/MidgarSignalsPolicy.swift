import Foundation

/// The thresholds that decide when events are sent. ``standard`` is what apps run; tests inject smaller or faster ones.
struct MidgarSignalsPolicy: Sendable {
    static let standard = MidgarSignalsPolicy(
        flushThreshold: 20,
        flushInterval: 60,
        minimumSpacing: 10,
        maximumBatchEvents: 50,
        maximumBatchBytes: 32 * 1024,
        maximumQueued: 500,
        defaultRetryAfter: 60,
        maximumRetryAfter: 3_600,
        persistInterval: 5
    )

    /// A flush starts as soon as this many events are queued.
    let flushThreshold: Int
    /// Seconds between flushes while events are waiting.
    let flushInterval: TimeInterval
    /// Seconds between two automatic requests.
    let minimumSpacing: TimeInterval
    let maximumBatchEvents: Int
    let maximumBatchBytes: Int
    /// The queue keeps at most this many events, dropping the oldest first.
    let maximumQueued: Int
    /// The wait after a 429 that carried no `Retry-After`.
    let defaultRetryAfter: TimeInterval
    /// A `Retry-After` above this is shortened to it.
    let maximumRetryAfter: TimeInterval
    /// Queued events and the uniqueness ledger are written to disk at most this many seconds after they change, and at once on a flush.
    let persistInterval: TimeInterval
}
