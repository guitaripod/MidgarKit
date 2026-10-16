import Foundation

/// How `MidgarHTTPClient` retries an idempotent request. `standard` is what production uses.
struct MidgarRetryPolicy: Sendable {
    static let standard = MidgarRetryPolicy(
        maximumAttempts: 3,
        baseDelay: 0.5,
        maximumDelay: 8,
        maximumRetryAfter: 60
    )

    let maximumAttempts: Int
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    /// A server asking for a longer wait than this ends the retries and surfaces the error.
    let maximumRetryAfter: TimeInterval

    /// The wait before the next attempt, or nil when the request should stop here.
    func delay(afterAttempt attempt: Int, retryAfter: TimeInterval?) -> TimeInterval? {
        guard let retryAfter else {
            return backoff(afterAttempt: attempt)
        }
        return retryAfter <= maximumRetryAfter ? retryAfter : nil
    }

    /// Exponential backoff capped at `maximumDelay`, scaled by a random factor between one half and one.
    private func backoff(afterAttempt attempt: Int) -> TimeInterval {
        let step = min(maximumDelay, baseDelay * pow(2, Double(attempt - 1)))
        return step * Double.random(in: 0.5...1)
    }
}

extension HTTPURLResponse {
    /// `Retry-After` as seconds from now, accepting both the delta-seconds and HTTP-date forms.
    var midgarRetryAfter: TimeInterval? {
        guard let value = value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty
        else {
            return nil
        }
        if let seconds = TimeInterval(value), seconds.isFinite {
            return max(0, seconds)
        }
        guard let date = Self.midgarHTTPDate(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSinceNow)
    }

    private static func midgarHTTPDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
