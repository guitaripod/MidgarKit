import Foundation
import MidgarCore

enum MidgarEvent: String {
    case portalOpen = "portal_open"
    case impression
    case tap
    case loaded
    case launch
    case overlay
}

/// Fire-and-forget, anonymous cross-promo telemetry, sent through ``MidgarSignals``. Each event carries the
/// promoted app id, the storefront and the placement; the host app is identified by the signals client's
/// `X-App-ID`. `overlay` is the App Store overlay that ``Midgar/moment(_:config:)`` presents. Nothing is sent while the host has not configured ``MidgarSignals/shared`` or when
/// ``MidgarConfig/enableTelemetry`` is off.
struct Telemetry {
    let config: MidgarConfig
    var signals: @Sendable () -> MidgarSignals? = { MidgarSignals.shared }

    func send(_ event: MidgarEvent, appId: String? = nil) {
        let telemetry = self
        Task.detached(priority: .background) {
            await telemetry.record(event, appId: appId)
        }
    }

    func record(_ event: MidgarEvent, appId: String? = nil) async {
        guard config.enableTelemetry, let signals = signals() else { return }
        await signals.record(event.rawValue, props: props(event, appId: appId))
    }

    /// The props the signals schema lists for the event: `portal_open` has no promoted app, the others
    /// carry its id. The storefront is left out when it is unknown.
    func props(_ event: MidgarEvent, appId: String?) -> [String: MidgarSignalValue] {
        var props: [String: MidgarSignalValue] = ["placement": .string(config.placement)]
        if let storefront = config.resolvedStorefront, !storefront.isEmpty {
            props["storefront"] = .string(storefront)
        }
        if event != .portalOpen, let appId {
            props["appId"] = .string(appId)
        }
        return props
    }
}
