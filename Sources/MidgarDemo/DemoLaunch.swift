import Foundation

/// The launch contract a screenshot run uses to turn an app into a demo. Every key is a launch argument
/// (`-MidgarDemo daily`) or the matching environment variable (`MIDGAR_DEMO=daily`); arguments win.
public struct DemoLaunch: Sendable, Equatable {
    /// One key of the contract, with its argument spelling and its environment spelling.
    public enum Key: String, CaseIterable, Sendable {
        case world = "MidgarDemo"
        case scene = "MidgarDemoScene"
        case date = "MidgarDemoDate"
        case locale = "MidgarDemoLocale"

        /// The argument as the command line spells it, with its leading dash.
        public var argument: String { "-" + rawValue }

        /// The environment variable that carries the same value.
        public var environmentName: String {
            switch self {
            case .world: "MIDGAR_DEMO"
            case .scene: "MIDGAR_DEMO_SCENE"
            case .date: "MIDGAR_DEMO_DATE"
            case .locale: "MIDGAR_DEMO_LOCALE"
            }
        }
    }

    public let world: String?
    public let scene: String?
    public let date: Date?
    public let locale: String?

    /// Demo mode is on exactly when a world is named. Scene, date and locale mean nothing without one.
    public var isEnabled: Bool { world != nil }

    public init(world: String?, scene: String?, date: Date?, locale: String?) {
        self.world = world
        self.scene = scene
        self.date = date
        self.locale = locale
    }

    /// The contract as this process was launched.
    public static var current: DemoLaunch {
        get throws {
            try parse(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
        }
    }

    /// Reads the contract from launch arguments and the environment. An argument with no value is an error;
    /// an empty environment variable counts as unset. A malformed date is an error even outside demo mode.
    public static func parse(arguments: [String], environment: [String: String]) throws -> DemoLaunch {
        let world = try value(.world, arguments: arguments, environment: environment)
        let scene = try value(.scene, arguments: arguments, environment: environment)
        let dateText = try value(.date, arguments: arguments, environment: environment)
        let locale = try value(.locale, arguments: arguments, environment: environment)
        return DemoLaunch(
            world: world,
            scene: scene,
            date: try dateText.map(parseDate),
            locale: locale
        )
    }

    /// The value for one key: the argument after it when present, otherwise the environment variable.
    private static func value(_ key: Key, arguments: [String], environment: [String: String]) throws -> String? {
        if let index = arguments.firstIndex(of: key.argument) {
            let candidate = arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            guard let candidate, !candidate.isEmpty, !candidate.hasPrefix("-") else {
                throw DemoError.missingValue(argument: key.argument)
            }
            return candidate
        }
        return environment[key.environmentName].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Accepts an internet date-time with a zone, with or without fractional seconds. A bare date is rejected:
    /// a frozen "now" needs an instant.
    private static func parseDate(_ text: String) throws -> Date {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: text) ?? plain.date(from: text) else {
            throw DemoError.malformedDate(text)
        }
        return date
    }
}
