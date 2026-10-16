import Foundation

/// The live pieces of one configuration: the os.Logger subsystem and the file writer.
struct LogRuntime: Sendable {
    let subsystem: String
    let writer: LogFileWriter

    init(configuration: LogConfiguration) {
        subsystem = configuration.subsystem
        writer = LogFileWriter(
            directory: configuration.directory,
            fileName: configuration.fileName,
            maxBytes: configuration.maxBytes,
            keepFiles: configuration.keepFiles
        )
    }
}

/// Holds the process-wide ``LogRuntime`` behind a lock.
///
/// `runtime` is the only mutable state and is read and written only inside `lock`. `LogRuntime` is immutable and Sendable, so handing it out of the lock is safe.
final class LogState: @unchecked Sendable {
    private let lock = NSLock()
    private var runtime: LogRuntime?

    func current(orCreate make: () -> LogRuntime) -> LogRuntime {
        lock.withLock {
            if let runtime {
                return runtime
            }
            let created = make()
            runtime = created
            return created
        }
    }

    func replace(with replacement: LogRuntime) -> LogRuntime? {
        lock.withLock {
            let previous = runtime
            runtime = replacement
            return previous
        }
    }
}
