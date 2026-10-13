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

    /// Where in the host app the portal was opened from. It is reported with every event and
    /// folded into the App Store campaign token so installs can be credited per placement.
    public var placement: String

    /// The App Store Connect provider token attached to product pages, so installs show up under
    /// App Analytics campaigns. `nil` sends the campaign token alone.
    public var providerToken: String?

    public init(
        endpoint: URL = MidgarConfig.defaultEndpoint,
        accent: MidgarColor? = nil,
        title: String = "More Apps",
        excludedBundleIDs: [String] = [],
        enableTelemetry: Bool = true,
        storefront: String? = nil,
        placement: String = "settings",
        providerToken: String? = MidgarConfig.defaultProviderToken
    ) {
        self.endpoint = endpoint
        self.accent = accent
        self.title = title
        self.excludedBundleIDs = excludedBundleIDs
        self.enableTelemetry = enableTelemetry
        self.storefront = storefront
        self.placement = placement
        self.providerToken = providerToken
    }

    /// The default configuration, pointing at the hosted Midgar catalog.
    public static let `default` = MidgarConfig()

    public static let defaultEndpoint = URL(string: "https://midgar-catalog.guitaripod.workers.dev")!

    public static let defaultProviderToken: String? = "120194828"
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

    /// The App Store campaign token for this host and placement, for example `psywave-settings`.
    /// Limited to the 40 characters Apple allows.
    var campaignToken: String {
        let host = (Bundle.main.bundleIdentifier ?? "app").split(separator: ".").last.map(String.init) ?? "app"
        let raw = "\(host)-\(placement)".lowercased()
        let allowed = raw.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return String(allowed.prefix(40))
    }

    var resolvedAccent: MidgarColor {
        #if canImport(UIKit)
        return accent ?? .tintColor
        #else
        return accent ?? .controlAccentColor
        #endif
    }
}
