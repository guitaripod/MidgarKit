import Foundation
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Entry points for the Midgar portal, the in-app universe of every Midgar app. UIKit on iOS / tvOS
/// / visionOS / Mac Catalyst, AppKit on native macOS. SwiftUI hosts use ``MidgarStoreView`` /
/// ``SwiftUI/View/midgarStore(isPresented:config:)``.
public enum Midgar {

    static let log = Logger(subsystem: "com.midgar.storefront", category: "Midgar")

    #if canImport(UIKit)

    /// Returns the portal view controller, ready to present or embed.
    @MainActor
    public static func makeStoreViewController(config: MidgarConfig = .default) -> UIViewController {
        MidgarPortalViewController(config: config)
    }

    /// Presents the portal full screen with an iris opening from the middle of the screen. Without
    /// an explicit presenter, the top-most view controller in the active scene is used. Returns
    /// `false` (and logs) when no presenter could be found.
    @discardableResult
    @MainActor
    public static func present(
        from presenter: UIViewController? = nil,
        config: MidgarConfig = .default,
        sourceView: UIView? = nil
    ) -> Bool {
        if let gate = config.gate {
            var ungated = config
            ungated.gate = nil
            Task { @MainActor in
                if await gate() { present(from: presenter, config: ungated, sourceView: sourceView) }
            }
            return true
        }
        guard let host = presenter ?? topViewController() else {
            log.error("Midgar.present found no view controller to present from; pass an explicit presenter.")
            assertionFailure("Midgar.present found no view controller to present from.")
            return false
        }
        let portal = MidgarPortalViewController(config: config, irisOrigin: irisOrigin(for: sourceView))
        portal.modalPresentationStyle = .fullScreen
        topMost(host).present(portal, animated: true)
        return true
    }

    /// The centre of `view` in window coordinates, where the iris should open from.
    @MainActor
    private static func irisOrigin(for view: UIView?) -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        return view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
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

    /// Returns the portal view controller, ready to present as a sheet or embed.
    @MainActor
    public static func makeStoreViewController(config: MidgarConfig = .default) -> NSViewController {
        MidgarPortalViewController(config: config)
    }

    /// Presents the portal as a sheet from the given (or key) window. Returns `false` if no window
    /// could be found.
    @discardableResult
    @MainActor
    public static func present(from presenter: NSViewController? = nil, config: MidgarConfig = .default) -> Bool {
        if let gate = config.gate {
            var ungated = config
            ungated.gate = nil
            Task { @MainActor in
                if await gate() { present(from: presenter, config: ungated) }
            }
            return true
        }
        let store = makeStoreViewController(config: config)
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
