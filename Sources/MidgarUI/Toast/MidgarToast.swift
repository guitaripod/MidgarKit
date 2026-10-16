import Foundation

/// A short message that appears over the content, then goes away on its own.
public struct MidgarToast: Identifiable, Hashable, Sendable {
    public enum Style: Sendable, Hashable, CaseIterable {
        case info
        case success
        case warning
        case error

        public var systemImage: String {
            switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var haptic: MidgarHapticEvent? {
            switch self {
            case .info: nil
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
    }

    public static let defaultDuration: TimeInterval = 2.5

    public let id: UUID
    public var message: String
    public var style: Style
    public var systemImage: String
    public var duration: TimeInterval

    public init(
        _ message: String,
        style: Style = .info,
        systemImage: String? = nil,
        duration: TimeInterval = MidgarToast.defaultDuration
    ) {
        self.id = UUID()
        self.message = message
        self.style = style
        self.systemImage = systemImage ?? style.systemImage
        self.duration = duration
    }

    public static func success(_ message: String) -> MidgarToast { MidgarToast(message, style: .success) }
    public static func warning(_ message: String) -> MidgarToast { MidgarToast(message, style: .warning) }
    public static func error(_ message: String) -> MidgarToast { MidgarToast(message, style: .error) }
}
