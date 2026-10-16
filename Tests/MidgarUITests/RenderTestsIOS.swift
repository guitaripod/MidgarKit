#if os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import MidgarUI

@Suite @MainActor struct RenderTestsIOS {
    private let size = CGSize(width: 420, height: 912)

    private func host<Content: View>(_ content: Content) -> UIViewController {
        UIHostingController(rootView: content.midgarTheme(RenderFixtures.theme))
    }

    /// Renders the controller's layer tree in a window that is never put on screen. A package test has no
    /// app scene, so `drawHierarchy` would capture nothing; rendering the layers works without one.
    private func snapshot(_ make: () -> UIViewController, dark: Bool, name: String) throws -> Data {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        window.overrideUserInterfaceStyle = style
        let controller = make()
        controller.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        replaceGlass(in: window)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            window.layer.render(in: context.cgContext)
        }
        let data = try #require(image.pngData())
        try dump(data, name: name, dark: dark)
        return data
    }

    /// `CALayer.render(in:)` draws nothing at all once a Liquid Glass button's `CASDFLayer` is in the tree, so
    /// the whole capture comes out transparent. Hides those layers and puts an accent capsule where each
    /// glass button was, which keeps the label legible; the glass material itself cannot be captured here.
    private func replaceGlass(in window: UIWindow) {
        let accent = UIColor(RenderFixtures.theme.accent.color).resolvedColor(with: window.traitCollection)
        var capsules: [(host: CALayer, frame: CGRect)] = []
        func visit(_ layer: CALayer) {
            let name = String(describing: type(of: layer))
            if name == "CASDFLayer" {
                layer.isHidden = true
            } else if name == "SDFLayer", let host = layer.superlayer {
                capsules.append((host, layer.frame))
                layer.sublayers?.forEach(visit)
            } else {
                layer.sublayers?.forEach(visit)
            }
        }
        visit(window.layer)
        for (host, frame) in capsules {
            let capsule = CALayer()
            capsule.frame = frame
            capsule.cornerRadius = frame.height / 2
            capsule.backgroundColor = accent.cgColor
            host.insertSublayer(capsule, at: 0)
        }
    }

    private func dump(_ data: Data, name: String, dark: Bool) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("ios-\(name)-\(dark ? "dark" : "light").png"))
    }

    private func distinctPixelCount(_ png: Data) -> Int {
        guard let cgImage = UIImage(data: png)?.cgImage else { return 0 }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var seen = Set<UInt32>()
        for index in Swift.stride(from: 0, to: bytes.count, by: 28) {
            seen.insert(UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]))
            if seen.count > 8 { break }
        }
        return seen.count
    }

    private func check(_ name: String, _ make: () -> UIViewController) throws {
        let light = try snapshot(make, dark: false, name: name)
        let dark = try snapshot(make, dark: true, name: name)
        #expect(distinctPixelCount(light) > 2, "\(name) light rendered blank")
        #expect(distinctPixelCount(dark) > 2, "\(name) dark rendered blank")
        #expect(light != dark, "\(name) looks the same in light and dark")
    }

    @Test func settingsRenders() throws {
        try check("settings") { host(RenderFixtures.settings()) }
    }

    @Test func onboardingRenders() throws {
        try check("onboarding") { host(RenderFixtures.onboarding()) }
    }

    @Test func whatsNewRenders() throws {
        try check("whats-new") { host(RenderFixtures.whatsNew()) }
    }

    @Test func toastRenders() throws {
        for style in MidgarToast.Style.allCases {
            try check("toast-\(style)") { host(RenderFixtures.toast(style)) }
        }
    }

    @Test func settingsViewControllerRenders() throws {
        try check("settings-controller") {
            MidgarSettingsViewController(sections: RenderFixtures.settingsSections, theme: RenderFixtures.theme) {
                RenderFixtures.portalCard
            }
        }
    }

    @Test func onboardingViewControllerRenders() throws {
        try check("onboarding-controller") {
            MidgarOnboardingViewController(pages: RenderFixtures.onboardingPages, theme: RenderFixtures.theme) {}
        }
    }

    @Test func whatsNewViewControllerRenders() throws {
        try check("whats-new-controller") {
            MidgarWhatsNewViewController(
                items: RenderFixtures.whatsNewItems,
                version: "1.4.2",
                store: MidgarWhatsNewStore(appID: "render-tests", defaults: makeDefaults()),
                theme: RenderFixtures.theme
            )
        }
    }

    @Test func toastPresenterRenders() throws {
        try check("toast-presenter") {
            let plain = UIViewController()
            plain.view.backgroundColor = .systemBackground
            plain.showMidgarToast(RenderFixtures.toastModel(.success), theme: RenderFixtures.theme)
            return plain
        }
    }
}
#endif
