import Foundation

/// Remembers whether the person finished onboarding, per app and per onboarding version.
/// Raising `version` shows onboarding again to everyone, for example after a flow that asks for new permissions.
public struct MidgarOnboardingStore: Sendable {
    public let appID: String
    public let version: Int

    private let defaults: MidgarDefaults

    public init(
        appID: String = Bundle.main.bundleIdentifier ?? "app",
        version: Int = 1,
        defaults: UserDefaults = .standard
    ) {
        self.appID = appID
        self.version = version
        self.defaults = MidgarDefaults(defaults)
    }

    public var key: String {
        "midgar.onboarding.\(appID).v\(version)"
    }

    public var hasCompleted: Bool {
        defaults.store.bool(forKey: key)
    }

    public var shouldPresent: Bool {
        !hasCompleted
    }

    public func markCompleted() {
        defaults.store.set(true, forKey: key)
    }

    /// Forgets that onboarding was completed, so the next launch shows it again. Settings can offer this as a row.
    public func showAgain() {
        defaults.store.removeObject(forKey: key)
    }
}
