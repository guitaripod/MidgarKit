import Foundation

/// An immutable snapshot of the app's remote config: the last verified document layered over the app's compiled defaults.
///
/// Reads never fail. A key the document lacks, or holds with another type, falls back to the compiled default of the right type, then to the `default` argument.
public struct MidgarConfig: Sendable, Equatable {
    public let version: Int?
    public let minVersion: String?
    private let values: [String: MidgarConfigValue]
    private let defaults: [String: MidgarConfigValue]
    private let kill: Set<String>

    /// A snapshot with no document: every read comes from the compiled defaults.
    public init(defaults: [String: MidgarConfigValue] = [:]) {
        self.version = nil
        self.minVersion = nil
        self.values = [:]
        self.defaults = defaults
        self.kill = []
    }

    init(document: MidgarConfigDocument, defaults: [String: MidgarConfigValue]) {
        self.version = document.version
        self.minVersion = document.minVersion
        self.values = document.values
        self.defaults = defaults
        self.kill = document.kill
    }

    /// True when a verified document backs this snapshot, false when it is compiled defaults only.
    public var isFromDocument: Bool {
        version != nil
    }

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        read(key, \.boolValue) ?? fallback
    }

    public func int(_ key: String, default fallback: Int) -> Int {
        read(key, \.intValue) ?? fallback
    }

    public func double(_ key: String, default fallback: Double) -> Double {
        read(key, \.doubleValue) ?? fallback
    }

    public func string(_ key: String, default fallback: String) -> String {
        read(key, \.stringValue) ?? fallback
    }

    /// True when the document lists the feature under `kill`. Compiled defaults never kill a feature.
    public func isKilled(_ feature: String) -> Bool {
        kill.contains(feature)
    }

    /// True when the document sets a `minVersion` above `currentVersion`. Versions compare numerically per dotted component, so `1.10.0` is above `1.9.9` and missing components count as zero. An unreadable version on either side never demands an update.
    public func requiresUpdate(currentVersion: String) -> Bool {
        guard let minVersion,
              let required = MidgarDottedVersion(minVersion),
              let current = MidgarDottedVersion(currentVersion)
        else {
            return false
        }
        return current < required
    }

    private func read<Value>(_ key: String, _ extract: (MidgarConfigValue) -> Value?) -> Value? {
        values[key].flatMap(extract) ?? defaults[key].flatMap(extract)
    }
}

/// A dotted numeric version such as `1.10.0`. A suffix after the digits of a component (`1.2.3-beta`) is ignored.
struct MidgarDottedVersion: Comparable {
    private let components: [Int]

    init?(_ text: String) {
        let parsed = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0.prefix { $0.isNumber }) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else {
            return nil
        }
        components = parsed.compactMap { $0 }
    }

    static func < (lhs: MidgarDottedVersion, rhs: MidgarDottedVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
