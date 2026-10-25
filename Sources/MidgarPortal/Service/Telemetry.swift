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
        guard config.enableTelemetry, let signals = signals(), let signal = signal(event, appId: appId) else { return }
        await signals.send(signal)
    }

    /// The typed signals event: `portal_open` has no promoted app, the others carry its id and are left out without one. The storefront is left out when it is not one the registry lists, and a placement the registry does not list (an app's own, such as `create`) is counted as `feature`, the generic in-app surface.
    func signal(_ event: MidgarEvent, appId: String?) -> MidgarSignal? {
        let placement = MidgarSignal.Placement(rawValue: config.placement) ?? .feature
        let storefront = config.resolvedStorefront.flatMap { MidgarSignal.Storefront(rawValue: $0) }
        if event == .portalOpen {
            return .portalOpen(storefront: storefront, placement: placement)
        }
        guard let appId else { return nil }
        switch event {
        case .portalOpen: return nil
        case .impression: return .impression(appId: appId, storefront: storefront, placement: placement)
        case .tap: return .tap(appId: appId, storefront: storefront, placement: placement)
        case .loaded: return .loaded(appId: appId, storefront: storefront, placement: placement)
        case .launch: return .launch(appId: appId, storefront: storefront, placement: placement)
        case .overlay: return .overlay(appId: appId, storefront: storefront, placement: placement)
        }
    }

    /// The props the signals schema lists for the event.
    func props(_ event: MidgarEvent, appId: String?) -> [String: MidgarSignalValue] {
        signal(event, appId: appId)?.props ?? [:]
    }
}
