import Foundation

enum MidgarEvent: String {
    case portalOpen = "portal_open"
    case impression
    case tap
    case loaded
    case launch
}

/// Fire-and-forget, anonymous cross-promo telemetry. Sends nothing identifying: only the promoted
/// app id, the promoting app's bundle id, the placement and the storefront. Honors
/// ``MidgarConfig/enableTelemetry``.
struct Telemetry {
    static let noApp = "0"

    let config: MidgarConfig
    var session: URLSession = .midgar

    func send(_ event: MidgarEvent, appId: String = Telemetry.noApp) {
        guard config.enableTelemetry else { return }
        var request = URLRequest(url: config.eventURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload(event, appId: appId))
        let session = session
        Task.detached(priority: .background) {
            _ = try? await session.data(for: request)
        }
    }

    func payload(_ event: MidgarEvent, appId: String) -> [String: String] {
        [
            "event": event.rawValue,
            "appId": appId,
            "source": config.sourceBundleID,
            "storefront": config.resolvedStorefront ?? "",
            "placement": config.placement,
        ]
    }
}
