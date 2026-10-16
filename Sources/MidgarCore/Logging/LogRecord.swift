import Foundation

/// One log event before it is formatted for the file.
struct LogRecord: Sendable {
    let date: Date
    let level: MidgarLog.Level
    let category: String
    let message: String

    /// The file line: ISO-8601 time, process id, level, category and message. Line breaks in the message are escaped so every record stays on one line.
    func line(timestamp: String, processID: Int32) -> String {
        "\(timestamp) [\(processID)] [\(Self.padded(level.rawValue, to: 6))] [\(Self.padded(category, to: 12))] \(escapedMessage)\n"
    }

    private var escapedMessage: String {
        message
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Pads with spaces up to `width` and never truncates, so a long category stays whole.
    private static func padded(_ value: String, to width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }
}
