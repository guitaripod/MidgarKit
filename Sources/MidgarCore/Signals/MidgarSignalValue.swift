import Foundation

/// A prop value an event may carry: a string, integer, double or boolean, which are the only types the signals schema accepts.
public enum MidgarSignalValue: Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// The longest string the server accepts, in UTF-16 units as JavaScript counts them.
    public static let maximumStringLength = 64

    /// The value as it is queued: strings cut to ``maximumStringLength``, and nil for a double that JSON cannot carry.
    var sanitized: MidgarSignalValue? {
        switch self {
        case .string(let text):
            return .string(Self.capped(text))
        case .double(let number):
            return number.isFinite ? self : nil
        case .int, .bool:
            return self
        }
    }

    /// Keeps whole characters while the UTF-16 length stays within the limit, so no character is split.
    static func capped(_ text: String) -> String {
        guard text.utf16.count > maximumStringLength else {
            return text
        }
        var result = ""
        var length = 0
        for character in text {
            length += character.utf16.count
            if length > maximumStringLength {
                break
            }
            result.append(character)
        }
        return result
    }
}

extension MidgarSignalValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension MidgarSignalValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}
