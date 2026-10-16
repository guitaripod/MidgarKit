import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Finds out which sibling apps are on this device without any network call or identifier. iOS
/// asks whether one of the app's URL schemes (its catalog slot such as `midgar-07`, its catalog
/// scheme, or its lowercased bundle id) can be opened, which needs a scheme in the host's
/// `LSApplicationQueriesSchemes`; macOS asks Launch Services directly.
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
        return installedURL(for: app) != nil
        #else
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) != nil
        #endif
    }

    /// The first URL of the app that `canOpen` accepts, trying the slot before the scheme and the
    /// legacy bundle-id scheme, or `nil` when the app cannot be reached by any of them.
    static func installedURL(for app: MidgarApp, canOpen: (URL) -> Bool) -> URL? {
        app.reachableSchemes
            .compactMap { URL(string: "\($0)://") }
            .first(where: canOpen)
    }

    #if canImport(UIKit)
    /// The URL that opens `app` on this device, using whichever of its schemes is declared and
    /// answers `canOpenURL`.
    @MainActor
    static func installedURL(for app: MidgarApp) -> URL? {
        installedURL(for: app) { UIApplication.shared.canOpenURL($0) }
    }
    #endif

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
        let missing = apps.filter { declared.isDisjoint(with: $0.reachableSchemes) }
        guard !missing.isEmpty else { return }
        log.notice("LSApplicationQueriesSchemes is missing \(missing.count) Midgar schemes; installed apps cannot be detected")
        #endif
    }
}
