import Foundation

enum MidgarEvent: String {
    case impression
    case tap
}

/// Fire-and-forget, anonymous cross-promo telemetry. Sends nothing identifying — only the promoted
/// app id, the promoting app's bundle id, and the storefront. Honors ``MidgarConfig/enableTelemetry``.
struct Telemetry {
    let config: MidgarConfig
    var session: URLSession = .midgar

    func send(_ event: MidgarEvent, appId: String) {
        guard config.enableTelemetry else { return }
        var request = URLRequest(url: config.eventURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: String] = [
            "event": event.rawValue,
            "appId": appId,
            "source": config.sourceBundleID,
            "storefront": config.resolvedStorefront ?? "",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        let session = session
        Task.detached(priority: .background) {
            _ = try? await session.data(for: request)
        }
    }
}
