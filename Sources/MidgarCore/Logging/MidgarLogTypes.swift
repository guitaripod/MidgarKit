import Foundation
#if canImport(OSLog)
import OSLog
#endif

extension MidgarLog {
    /// A named stream of log lines, written to the file as `[raw value]`. Apps add their own with `static let store = MidgarLog.Category("store")`.
    public struct Category: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The severity of one line, written to the file as its raw value.
    enum Level: String, Sendable {
        case debug
        case info
        case notice
        case error
        case fault
    }
}

extension MidgarLog.Category {
    public static let general = MidgarLog.Category("general")
    public static let network = MidgarLog.Category("network")
    public static let commerce = MidgarLog.Category("commerce")
    public static let account = MidgarLog.Category("account")
    public static let portal = MidgarLog.Category("portal")
    public static let ui = MidgarLog.Category("ui")
}

#if canImport(OSLog)
extension MidgarLog.Level {
    /// The os.Logger type for this level. Warnings are not an os.Logger level, so they travel as `notice`.
    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
    }
}
#endif
