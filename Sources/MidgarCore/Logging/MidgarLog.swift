import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// The one file and os.Logger logger every Midgar app uses.
///
/// Call ``configure(subsystem:fileName:maxBytes:keepFiles:)`` once at launch. Each call goes to `os.Logger` and appends one line to `Library/Logs/<fileName>` in the app container, the path `devicectl device copy from` reads in the ios-device-logs workflow. File lines are written on a serial utility queue in call order, and ``flush()`` runs automatically when the app backgrounds or terminates.
public enum MidgarLog {
    private static let state = LogState()

    /// Sets the subsystem, log file and rotation policy. Call once at launch; a later call replaces the earlier configuration.
    public static func configure(
        subsystem: String = Bundle.main.bundleIdentifier ?? "app.midgar",
        fileName: String = "app.log",
        maxBytes: UInt64 = 2 * 1024 * 1024,
        keepFiles: Int = 3
    ) {
        install(LogConfiguration(
            subsystem: subsystem,
            directory: LogConfiguration.standardDirectory,
            fileName: fileName,
            maxBytes: maxBytes,
            keepFiles: keepFiles
        ))
    }

    /// Verbose detail for development. Written without an immediate disk sync.
    public static func debug(_ message: String, category: Category = .general) {
        record(.debug, message, category: category)
    }

    /// Routine progress worth keeping in a field log.
    public static func info(_ message: String, category: Category = .general) {
        record(.info, message, category: category)
    }

    /// A noteworthy event that is not a failure. ``AppLogger`` maps its warnings here.
    public static func notice(_ message: String, category: Category = .general) {
        record(.notice, message, category: category)
    }

    /// A failure the user or support may need to see.
    public static func error(_ message: String, category: Category = .general) {
        record(.error, message, category: category)
    }

    /// An unrecoverable failure, written before the app is likely to stop.
    public static func fault(_ message: String, category: Category = .general) {
        record(.fault, message, category: category)
    }

    /// Waits until every line logged so far is written and synced to disk.
    public static func flush() {
        currentRuntime().writer.flush()
    }

    /// The log files that exist now, newest first: the current file, then its archives.
    public static var logFileURLs: [URL] {
        currentRuntime().writer.existingFileURLs()
    }

    /// Masks bearer tokens, email addresses, hex strings of 32 or more characters and base64 strings of 40 or more characters that contain a digit or a symbol. Every logged message passes through this before it is written.
    public static func redacting(_ text: String) -> String {
        LogRedactor.redact(text)
    }

    /// Replaces the process-wide runtime and flushes the one it replaces.
    static func install(_ configuration: LogConfiguration) {
        _ = lifecycleObservers
        state.replace(with: LogRuntime(configuration: configuration))?.writer.flush()
    }

    private static func currentRuntime() -> LogRuntime {
        _ = lifecycleObservers
        return state.current { LogRuntime(configuration: .standard) }
    }

    private static func record(_ level: Level, _ message: String, category: Category) {
        let runtime = currentRuntime()
        let safeMessage = redacting(message)
        emitToOSLog(level, safeMessage, subsystem: runtime.subsystem, category: category.rawValue)
        runtime.writer.append(LogRecord(
            date: Date(),
            level: level,
            category: category.rawValue,
            message: safeMessage
        ))
    }

    /// Sends the line to os.Logger with public privacy, because the redacted message is already safe to show.
    private static func emitToOSLog(_ level: Level, _ message: String, subsystem: String, category: String) {
        #if canImport(OSLog)
        Logger(subsystem: subsystem, category: category).log(level: level.osLogType, "\(message, privacy: .public)")
        #endif
    }

    private static let lifecycleObservers: Void = {
        for name in lifecycleNotifications {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                MidgarLog.flush()
            }
        }
    }()

    /// The background and termination notifications, named by their raw values so MidgarCore never imports a UI framework.
    private static var lifecycleNotifications: [Notification.Name] {
        #if os(macOS)
        [
            Notification.Name("NSApplicationDidResignActiveNotification"),
            Notification.Name("NSApplicationWillTerminateNotification")
        ]
        #elseif os(iOS) || os(tvOS) || os(visionOS)
        [
            Notification.Name("UIApplicationDidEnterBackgroundNotification"),
            Notification.Name("UIApplicationWillTerminateNotification")
        ]
        #else
        []
        #endif
    }
}
