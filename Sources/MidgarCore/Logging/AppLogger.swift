import Foundation

/// The call shape of the per-app loggers that MidgarCore.Logging replaces. Every call forwards to ``MidgarLog``.
public enum AppLogger {
    public static func debug(_ message: String, category: MidgarLog.Category = .general) {
        MidgarLog.debug(message, category: category)
    }

    public static func info(_ message: String, category: MidgarLog.Category = .general) {
        MidgarLog.info(message, category: category)
    }

    /// Forwards to ``MidgarLog/notice(_:category:)``, the level that carries warnings in os.Logger.
    public static func warning(_ message: String, category: MidgarLog.Category = .general) {
        MidgarLog.notice(message, category: category)
    }

    public static func error(_ message: String, category: MidgarLog.Category = .general) {
        MidgarLog.error(message, category: category)
    }
}
