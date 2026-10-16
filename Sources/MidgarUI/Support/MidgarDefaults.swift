import Foundation

/// A `UserDefaults` that can cross concurrency domains.
/// `@unchecked Sendable` is safe because Apple documents `UserDefaults` as thread-safe and this wrapper never mutates its reference.
struct MidgarDefaults: @unchecked Sendable {
    let store: UserDefaults

    init(_ store: UserDefaults) {
        self.store = store
    }
}
