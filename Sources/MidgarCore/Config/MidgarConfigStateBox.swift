import Foundation

/// The current snapshot and the change subscribers, readable from any thread.
///
/// `@unchecked Sendable` is sound because the NSLock guards both mutable fields and nothing is yielded while it is held.
final class MidgarConfigStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: MidgarConfig
    private var continuations: [UUID: AsyncStream<MidgarConfig>.Continuation] = [:]

    init(_ snapshot: MidgarConfig) {
        self.snapshot = snapshot
    }

    var current: MidgarConfig {
        lock.withLock { snapshot }
    }

    func publish(_ next: MidgarConfig) {
        let targets = lock.withLock {
            snapshot = next
            return Array(continuations.values)
        }
        for continuation in targets {
            continuation.yield(next)
        }
    }

    func subscribe() -> AsyncStream<MidgarConfig> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: MidgarConfig.self, bufferingPolicy: .bufferingNewest(1))
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.unsubscribe(id)
        }
        return stream
    }

    private func unsubscribe(_ id: UUID) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }
}
