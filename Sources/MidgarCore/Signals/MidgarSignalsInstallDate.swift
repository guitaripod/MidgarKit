import Foundation

/// When this app was installed on this device, as far as the device knows, and the cohort that follows from it.
enum MidgarSignalsInstallDate {
    /// An install date before this is a placeholder (a restored backup or a reset clock), not a real install, and counts as `legacy`.
    static let earliestPlausible = Date(timeIntervalSince1970: 1_577_836_800)

    /// The creation date of the app's own container, which the system makes at install, keeps across updates and removes with a reinstall. On iOS, tvOS, visionOS and a sandboxed Mac app that is the home directory. A Mac app outside the sandbox has no container, so it is the folder `<Application Support>/<bundle id>` if it exists. Nil when there is no such folder or its attribute cannot be read.
    static func ofThisApp(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) -> Date? {
        creationDate(of: containerURL(fileManager: fileManager, environment: environment), fileManager: fileManager)
    }

    private static func containerURL(fileManager: FileManager, environment: [String: String]) -> URL? {
        #if os(macOS)
        if environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        guard let bundleID = Bundle.main.bundleIdentifier,
              let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return support.appendingPathComponent(bundleID, isDirectory: true)
        #else
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }

    static func creationDate(of url: URL?, fileManager: FileManager) -> Date? {
        guard let url, let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attributes[.creationDate] as? Date
    }

    /// The cohort of an install made at `installedAt`: the ISO week (`YYYY-Www`) of that date, `now` for a date in the future, `legacy` for a date before 2020, and the week of `now`, the first launch, when the date is unknown.
    static func cohort(installedAt: Date?, now: Date, calendar: Calendar) -> String {
        guard let installedAt else {
            return MidgarSignals.periodKey(.week, at: now, calendar: calendar)
        }
        guard installedAt >= earliestPlausible else {
            return MidgarSignalsCohortStore.legacy
        }
        return MidgarSignals.periodKey(.week, at: min(installedAt, now), calendar: calendar)
    }
}
