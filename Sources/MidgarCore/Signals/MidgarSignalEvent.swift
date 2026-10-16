import Foundation

/// One queued event: its name and the props the caller passed, nothing else.
struct MidgarSignalEvent: Codable, Sendable, Equatable {
    let name: String
    let props: [String: MidgarSignalValue]

    /// Builds the event the queue stores: the name cut to 64 characters, every string prop cut to 64, props with an empty key or a non-finite number left out. Nil for an empty name.
    init?(name: String, props: [String: MidgarSignalValue]) {
        let trimmed = MidgarSignalValue.capped(name)
        guard !trimmed.isEmpty else {
            return nil
        }
        self.name = trimmed
        var kept: [String: MidgarSignalValue] = [:]
        for (key, value) in props where !key.isEmpty {
            if let clean = value.sanitized {
                kept[MidgarSignalValue.capped(key)] = clean
            }
        }
        self.props = kept
    }
}

/// The request body, `{ "events": [ ... ] }`.
struct MidgarSignalBatch: Encodable, Sendable {
    let events: [MidgarSignalEvent]
}
