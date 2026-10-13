import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Finds out which sibling apps are on this device without any network call or identifier. iOS
/// asks whether the app's URL scheme (its lowercased bundle id) can be opened, which needs the
/// scheme in the host's `LSApplicationQueriesSchemes`; macOS asks Launch Services directly.
enum InstalledApps {
    private static let log = Logger(subsystem: "com.midgar.storefront", category: "Installed")

    /// Lowercased bundle identifiers of the apps in `apps` that are installed here.
    @MainActor
    static func detect(in apps: [MidgarApp]) -> Set<String> {
        var found = Set<String>()
        for app in apps where isInstalled(app) {
            found.insert(app.bundleId.lowercased())
        }
        return found
    }

    @MainActor
    static func isInstalled(_ app: MidgarApp) -> Bool {
        #if canImport(UIKit)
        guard let url = launchURL(for: app) else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) != nil
        #endif
    }

    static func launchURL(for app: MidgarApp) -> URL? {
        URL(string: "\(app.urlScheme)://")
    }

    /// Logs once when the host forgot to declare the schemes, which silently disables "Open".
    static func warnIfSchemesMissing(for apps: [MidgarApp]) {
        #if canImport(UIKit)
        let declared = Set(
            (Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] ?? [])
                .map { $0.lowercased() }
        )
        let missing = apps.filter { !declared.contains($0.urlScheme) }
        guard !missing.isEmpty else { return }
        log.notice("LSApplicationQueriesSchemes is missing \(missing.count) Midgar schemes; installed apps cannot be detected")
        #endif
    }
}
