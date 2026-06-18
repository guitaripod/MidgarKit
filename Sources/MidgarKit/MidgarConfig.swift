import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Configuration for a Midgar in-app storefront.
///
/// Pass an instance to ``Midgar/present(from:config:)`` or ``MidgarStoreViewController``. All values
/// have production-ready defaults; the host app's own bundle identifier is excluded automatically so
/// an app never advertises itself.
public struct MidgarConfig: Sendable {

    /// Base URL of the Midgar catalog service. Both `/v1/catalog` and `/v1/event` hang off this.
    public var endpoint: URL

    /// Tint applied to the navigation bar and the GET buttons. `nil` inherits the presenter's tint.
    public var accent: MidgarColor?

    /// Title shown at the top of the storefront.
    public var title: String

    /// Bundle identifiers never shown in the list. The host app's own identifier is always added.
    public var excludedBundleIDs: [String]

    /// When `true`, anonymous impression/tap counts are reported to the catalog service.
    public var enableTelemetry: Bool

    /// Two-letter App Store country override (e.g. `"us"`). `nil` uses the device region.
    public var storefront: String?

    public init(
        endpoint: URL = MidgarConfig.defaultEndpoint,
        accent: MidgarColor? = nil,
        title: String = "More Apps",
        excludedBundleIDs: [String] = [],
        enableTelemetry: Bool = true,
        storefront: String? = nil
    ) {
        self.endpoint = endpoint
        self.accent = accent
        self.title = title
        self.excludedBundleIDs = excludedBundleIDs
        self.enableTelemetry = enableTelemetry
        self.storefront = storefront
    }

    /// The default configuration, pointing at the hosted Midgar catalog.
    public static let `default` = MidgarConfig()

    public static let defaultEndpoint = URL(string: "https://midgar-catalog.guitaripod.workers.dev")!
}

extension MidgarConfig {
    var catalogURL: URL { endpoint.appending(path: "v1/catalog") }
    var eventURL: URL { endpoint.appending(path: "v1/event") }

    var sourceBundleID: String { Bundle.main.bundleIdentifier ?? "unknown" }

    var resolvedExclusions: [String] {
        var ids = excludedBundleIDs
        if let own = Bundle.main.bundleIdentifier { ids.append(own) }
        return Array(Set(ids.map { $0.lowercased() }))
    }

    var resolvedStorefront: String? {
        if let storefront, !storefront.isEmpty { return storefront.lowercased() }
        return Locale.current.region?.identifier.lowercased()
    }

    var resolvedAccent: MidgarColor {
        #if canImport(UIKit)
        return accent ?? .tintColor
        #else
        return accent ?? .controlAccentColor
        #endif
    }
}
