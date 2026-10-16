import Foundation

/// The highest document version ever accepted for one app, kept in a `UserDefaults` suite apart from the cache file. The cache is a plain file in Application Support that a restore, a backup swap or a deleted container can replace with an older document; the floor survives that, so an older signed document, which still verifies, cannot be served back to lift a kill switch or a `minVersion`.
///
/// Unchecked because `UserDefaults` is documented as thread safe but is not declared `Sendable` on every platform; the struct holds nothing else mutable.
struct MidgarConfigFloor: @unchecked Sendable {
    static let suiteName = "cc.midgarcorp.midgarkit.config"

    private let defaults: UserDefaults
    private let key: String

    /// - Parameter defaults: Where the floor lives. Defaults to the Midgar suite; tests pass their own.
    init(defaults: UserDefaults?, slug: String) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
        self.key = "floor.\(slug)"
    }

    var version: Int {
        defaults.integer(forKey: key)
    }

    /// Stores the version when it is above the current floor. The floor never goes down.
    func raise(to version: Int) {
        if version > self.version {
            defaults.set(version, forKey: key)
        }
    }
}
