import Foundation

/// A scalar from a config document's `values` object or from an app's compiled defaults. Nested objects and arrays are not supported and are dropped when a document is read.
public enum MidgarConfigValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// Integers widen to doubles, so a document may write `2` for a double key.
    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        case .bool, .string: return nil
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

extension MidgarConfigValue: ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(floatLiteral value: Double) {
        self = .double(value)
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

/// Decodes one JSON value, yielding nil for null, objects and arrays instead of failing the whole document.
struct LenientConfigValue: Decodable {
    let value: MidgarConfigValue?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            value = .double(double)
        } else if let string = try? container.decode(String.self) {
            value = .string(string)
        } else {
            value = nil
        }
    }
}
