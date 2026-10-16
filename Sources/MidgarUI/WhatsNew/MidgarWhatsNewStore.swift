import Foundation

/// Remembers the last app version whose What's New sheet was shown, per app.
public struct MidgarWhatsNewStore: Sendable {
    public let appID: String

    private let defaults: MidgarDefaults

    public init(appID: String = Bundle.main.bundleIdentifier ?? "app", defaults: UserDefaults = .standard) {
        self.appID = appID
        self.defaults = MidgarDefaults(defaults)
    }

    public var key: String {
        "midgar.whatsNew.\(appID).lastShownVersion"
    }

    public var lastShownVersion: String? {
        defaults.store.string(forKey: key)
    }

    /// Whether the sheet for `version` is due: the person has seen an older version before, or has never seen one and
    /// `showOnFirstInstall` is set. Downgrades and repeat launches of the same version never show it.
    public func shouldShow(for version: String, showOnFirstInstall: Bool = false) -> Bool {
        guard let last = lastShownVersion else { return showOnFirstInstall }
        return version.compare(last, options: .numeric) == .orderedDescending
    }

    public func markShown(_ version: String) {
        defaults.store.set(version, forKey: key)
    }

    /// Records a fresh install's version without showing anything, so the first update after it does show.
    public func recordInstallIfNeeded(version: String) {
        guard lastShownVersion == nil else { return }
        markShown(version)
    }

    /// Forgets what was shown, so the sheet is due again on the next check with `showOnFirstInstall`.
    public func reset() {
        defaults.store.removeObject(forKey: key)
    }
}
