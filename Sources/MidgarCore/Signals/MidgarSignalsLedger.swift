import Foundation

/// What this install has already sent, per event and prop combination, so an event that may be sent once per period or once per install is not sent twice. It holds names of periods, never a time or an identifier.
struct MidgarSignalsLedger: Sendable, Equatable {
    /// The mark of an entry that never expires.
    static let lifetimeMark = "lifetime"

    /// The most entries kept. Past it an event is sent without being remembered, so a flood of distinct props costs duplicates, never memory.
    static let capacity = 4_096

    private(set) var marks: [String: String]

    init(marks: [String: String] = [:]) {
        self.marks = marks
    }

    var isEmpty: Bool {
        marks.isEmpty
    }

    /// True, and remembers the mark, when `key` has not been sent under `mark` yet.
    mutating func claim(key: String, mark: String) -> Bool {
        if marks[key] == mark {
            return false
        }
        if marks[key] != nil || marks.count < Self.capacity {
            marks[key] = mark
        }
        return true
    }

    /// Drops the entries of periods that have passed. Returns whether anything went.
    @discardableResult
    mutating func prune(keeping current: MidgarSignalPeriodKeys) -> Bool {
        let before = marks.count
        marks = marks.filter { $0.value == Self.lifetimeMark || current.isCurrent($0.value) }
        return marks.count != before
    }

    /// The key of one event with one combination of props: the name and the props in name order.
    static func key(name: String, props: [String: MidgarSignalValue]) -> String {
        guard !props.isEmpty else {
            return name
        }
        var key = name
        for prop in props.sorted(by: { $0.key < $1.key }) {
            key += "|\(prop.key)=\(prop.value.ledgerText)"
        }
        return key
    }
}

extension MidgarSignalValue {
    fileprivate var ledgerText: String {
        switch self {
        case .string(let text): return text
        case .int(let number): return String(number)
        case .double(let number): return String(number)
        case .bool(let flag): return flag ? "true" : "false"
        }
    }
}

/// The uniqueness ledger on disk, `<directory>/signals-ledger-<app>.json`.
struct MidgarSignalsLedgerStore: Sendable {
    let fileURL: URL

    init(store: MidgarSignalsStore) {
        fileURL = store.sibling("ledger")
    }

    /// What the file holds, or an empty ledger when it is missing or unreadable.
    func load() -> MidgarSignalsLedger {
        guard let data = try? Data(contentsOf: fileURL), let marks = try? JSONDecoder().decode([String: String].self, from: data) else {
            return MidgarSignalsLedger()
        }
        return MidgarSignalsLedger(marks: marks)
    }

    func save(_ ledger: MidgarSignalsLedger) {
        guard !ledger.isEmpty else {
            delete()
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger.marks).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The week this install first ran Lifestream, kept in `<directory>/signals-cohort-<app>.json` and decided once. Opting out keeps it, so a person who turns counts back on stays in the cohort they were in.
struct MidgarSignalsCohortStore: Sendable {
    static let legacy = "legacy"

    let fileURL: URL

    init(store: MidgarSignalsStore) {
        fileURL = store.sibling("cohort")
    }

    func load() -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let cohort = try? JSONDecoder().decode([String: String].self, from: data)["cohort"],
              !cohort.isEmpty
        else {
            return nil
        }
        return cohort
    }

    func save(_ cohort: String) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(["cohort": cohort]).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

/// Whether the person lets this app send usage counts, `<directory>/signals-consent-<app>.json`. The file exists only while counts are off, so the default is on. The flag is read from any thread; the lock guards the one field, which is what makes the unchecked conformance sound.
final class MidgarSignalsConsent: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var enabled: Bool

    init(store: MidgarSignalsStore) {
        fileURL = store.sibling("consent")
        enabled = !FileManager.default.fileExists(atPath: fileURL.path)
    }

    var isEnabled: Bool {
        lock.withLock { enabled }
    }

    /// Sets the flag and returns whether it changed.
    func update(_ value: Bool) -> Bool {
        lock.withLock {
            defer { enabled = value }
            return enabled != value
        }
    }

    /// Makes the file match the flag.
    func persist() {
        if isEnabled {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(#"{"enabled":false}"#.utf8).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
