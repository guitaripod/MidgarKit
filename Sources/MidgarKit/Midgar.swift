import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Entry points for the Midgar in-app storefront. UIKit on iOS / tvOS / visionOS / Mac Catalyst,
/// AppKit on native macOS. SwiftUI hosts use ``MidgarStoreView`` / ``SwiftUI/View/midgarStore(isPresented:config:)``.
public enum Midgar {

    static let log = Logger(subsystem: "com.midgar.storefront", category: "Midgar")

    #if canImport(UIKit)

    /// Returns the storefront wrapped in a navigation controller, ready to present or embed.
    @MainActor
    public static func makeStoreViewController(config: MidgarConfig = .default) -> UIViewController {
        let store = MidgarStoreViewController(config: config)
        let navigation = UINavigationController(rootViewController: store)
        navigation.navigationBar.prefersLargeTitles = true
        if let accent = config.accent { navigation.view.tintColor = accent }
        return navigation
    }

    /// Presents the storefront modally. Without an explicit presenter, the top-most view controller
    /// in the active scene is used. Returns `false` (and logs) when no presenter could be found.
    @discardableResult
    @MainActor
    public static func present(from presenter: UIViewController? = nil, config: MidgarConfig = .default) -> Bool {
        guard let host = presenter ?? topViewController() else {
            log.error("Midgar.present found no view controller to present from; pass an explicit presenter.")
            assertionFailure("Midgar.present found no view controller to present from.")
            return false
        }
        let navigation = makeStoreViewController(config: config)
        navigation.modalPresentationStyle = .automatic
        host.present(navigation, animated: true)
        return true
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController
        return root.map(topMost)
    }

    @MainActor
    private static func topMost(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController { return topMost(presented) }
        if let nav = controller as? UINavigationController, let visible = nav.visibleViewController { return topMost(visible) }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController { return topMost(selected) }
        return controller
    }

    #elseif canImport(AppKit)

    /// Returns the storefront view controller, ready to present as a sheet or embed.
    @MainActor
    public static func makeStoreViewController(config: MidgarConfig = .default) -> NSViewController {
        MidgarStoreViewController(config: config)
    }

    /// Presents the storefront as a sheet from the given (or key) window. Returns `false` if no
    /// window could be found.
    @discardableResult
    @MainActor
    public static func present(from presenter: NSViewController? = nil, config: MidgarConfig = .default) -> Bool {
        let store = MidgarStoreViewController(config: config)
        if let presenter {
            presenter.presentAsSheet(store)
            return true
        }
        guard let host = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentViewController else {
            log.error("Midgar.present found no window to present from; pass an explicit presenter.")
            assertionFailure("Midgar.present found no window to present from.")
            return false
        }
        host.presentAsSheet(store)
        return true
    }

    #endif
}
