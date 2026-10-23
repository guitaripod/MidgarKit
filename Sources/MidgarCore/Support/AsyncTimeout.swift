import Foundation

/// Bounds an async call that may never return. A task group cannot do this: it waits for every child, including a hung one, before it returns. Here the caller is released when the deadline passes, and the operation is cancelled and left to wind down on its own.
public enum AsyncTimeout {
    /// Thrown by ``run(for:operation:)`` when the operation did not finish within its time.
    public struct Expired: Error, Sendable, Equatable {
        public init() {}
    }

    /// Runs `operation` and returns its value, rethrows its error, or throws ``Expired`` once `duration` has passed first. Never waits longer than `duration`, even when `operation` ignores cancellation.
    public static func run<T: Sendable>(
        for duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { continuation in
            let work = Task {
                do {
                    let value = try await operation()
                    if gate.claim() { continuation.resume(returning: value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(for: duration)
                if gate.claim() {
                    work.cancel()
                    continuation.resume(throwing: Expired())
                }
            }
        }
    }

    /// Lets exactly one of the racing tasks resume the continuation.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.withLock {
                guard !claimed else { return false }
                claimed = true
                return true
            }
        }
    }
}
