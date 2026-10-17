#if (os(iOS) || os(visionOS)) && !targetEnvironment(macCatalyst)
import StoreKit
import UIKit

/// Presents the App Store overlay in the foreground window scene.
@MainActor
final class SKOverlayPresenter: MomentPresenting {
    func present(_ app: MidgarApp, campaignToken: String, providerToken: String?) -> Bool {
        guard let scene = activeScene() else { return false }
        let configuration = SKOverlay.AppConfiguration(appIdentifier: app.appId, position: .bottom)
        configuration.campaignToken = campaignToken
        configuration.providerToken = providerToken
        configuration.userDismissible = true
        SKOverlay(configuration: configuration).present(in: scene)
        return true
    }

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
#endif
