import Foundation
import StoreKit
import StoreKitTest
import SwiftUI
import Testing
@testable import MidgarCommerce
import MidgarCore
import MidgarUI
@testable import MidgarCommerceUI

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The real paywall over the real StoreKit views, run from the StoreKit host app because `SubscriptionStoreView` and `StoreView` need StoreKit testing and an app scene. The package excludes this file, `Paywall.storekit` and `Tests/StoreKitHost` runs them. Each test writes light and dark PNGs to `MIDGAR_SNAPSHOT_DIR` (pass it to `xcodebuild` as `TEST_RUNNER_MIDGAR_SNAPSHOT_DIR`) so a person can look at them.
@Suite(.serialized) @MainActor struct PaywallSnapshotTests {
    static let group = "22000001"
    static let yearly = "app.midgar.test.yearly"
    static let monthly = "app.midgar.test.monthly"
    static let lifetime = "app.midgar.test.lifetime"
    static let theme = MidgarTheme(accent: MidgarColor(hex: 0x2A9D8F))
    static let links = MidgarPaywallLinks(
        termsOfUse: URL(string: "https://midgarcorp.cc/terms")!,
        privacyPolicy: URL(string: "https://midgarcorp.cc/privacy")!
    )

    struct Live {
        let store: MidgarStore
        let session: SKTestSession
    }

    func makeLive() async throws -> Live {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "Paywall", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        let ledger = FakeLedger()
        ledger.serve(midgarId: FakeIdentity.first, environment: "Sandbox")
        let identity = FakeIdentity()
        let store = MidgarStore(
            configuration: MidgarStoreConfiguration(
                appID: "app-test",
                productIDs: [Self.yearly, Self.monthly, Self.lifetime],
                entitlementsByProduct: [Self.yearly: "pro", Self.monthly: "pro", Self.lifetime: "pro"],
                directory: FileManager.default.temporaryDirectory.appendingPathComponent("paywall-" + UUID().uuidString, isDirectory: true)
            ),
            identity: identity,
            http: makeStubClient(ledger, tokenProvider: { try await identity.midgarId }),
            storeKit: LiveStoreKit(),
            clock: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            signal: { _, _ in },
            logger: { _ in },
            observesForeground: false
        )
        let loaded = try await store.products()
        #expect(loaded.count == 3, "StoreKit testing served \(loaded.map(\.id)) from Paywall.storekit")
        await waitForIntroOfferEligibility()
        return Live(store: store, session: session)
    }

    /// A purchase in an earlier test uses up the introductory offer, and StoreKit takes a moment to give it back after the session reset. Waiting here keeps every test independent of the order they run in.
    private func waitForIntroOfferEligibility() async {
        for _ in 0..<40 {
            if await Product.SubscriptionInfo.isEligibleForIntroOffer(for: Self.group) {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func settle() async {
        try? await Task.sleep(for: .seconds(3))
    }

    func write(_ data: Data, name: String, dark: Bool?) throws {
        let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"] ?? ""
        guard !path.isEmpty else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let appearance = dark.map { $0 ? "dark" : "light" } ?? "default"
        try data.write(to: directory.appendingPathComponent("\(Self.platformName)-\(name)-\(appearance).png"))
    }

    /// Renders `content` in each appearance the platform has and writes one PNG per appearance. `size` is the window to render in, the whole screen when nil.
    func capture<Content: View>(_ content: @autoclosure () -> Content, name: String, size: CGSize? = nil, scrolledToEnd: Bool = false) async throws {
        for dark in Self.appearances {
            let png = try await render(content().midgarTheme(Self.theme), dark: dark ?? false, size: size, scrolledToEnd: scrolledToEnd)
            try write(png, name: name, dark: dark)
            #expect(Self.distinctColors(in: png) > 4, "\(name) rendered blank")
        }
    }

    @Test func paywallRendersTheSubscriptionGroupWithEveryLegalPart() async throws {
        let live = try await makeLive()
        try await capture(
            MidgarPaywall(
                groupID: Self.group,
                store: live.store,
                links: Self.links,
                title: "Go Pro",
                subtitle: "Everything unlocked, on every device.",
                systemImage: "sparkles"
            ),
            name: "paywall"
        )
        await live.store.stop()
    }

    @Test func storefrontRendersOneTimeProductsAsPlanCards() async throws {
        let live = try await makeLive()
        try await capture(
            MidgarStorefront(
                productIDs: [Self.lifetime],
                store: live.store,
                links: Self.links,
                title: "Own it forever",
                subtitle: "One payment, no subscription.",
                systemImage: "infinity"
            ),
            name: "storefront"
        )
        await live.store.stop()
    }

    @Test func aPlanCardForARealProductTakesItsPriceAndTrialFromStoreKit() async throws {
        let live = try await makeLive()
        let products = try await Product.products(for: [Self.yearly, Self.monthly, Self.lifetime])
        let policy = MidgarTrialPolicy()
        let presentations = try await policy.presentations(for: [Self.yearly, Self.monthly])
        let ordered = [Self.yearly, Self.monthly, Self.lifetime].compactMap { id in products.first { $0.id == id } }

        #expect(presentations[Self.yearly]?.summary == "1 week free, then $39.99/year")
        #expect(presentations[Self.monthly] == nil)
        try await capture(
            VStack(spacing: 12) {
                ForEach(ordered, id: \.id) { product in
                    MidgarPlanCard(product: product, presentation: presentations[product.id], isSelected: product.id == Self.yearly)
                }
            }
            .padding(16),
            name: "plan-cards-storekit"
        )
        await live.store.stop()
    }

    @Test func theTrialPolicyAgreesWithStoreKitOnEligibility() async throws {
        let live = try await makeLive()
        let policy = MidgarTrialPolicy()

        #expect(await policy.isEligibleForIntroOffer(inGroup: Self.group) == (await Product.SubscriptionInfo.isEligibleForIntroOffer(for: Self.group)))
        live.session.clearTransactions()
        await live.store.stop()
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
extension PaywallSnapshotTests {
    static var platformName: String {
        #if os(tvOS)
        "tvos"
        #elseif os(visionOS)
        "visionos"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }

    /// visionOS draws every window on its own glass, so it has one appearance to look at.
    static var appearances: [Bool?] {
        #if os(visionOS)
        [nil]
        #else
        [false, true]
        #endif
    }

    func render<Content: View>(_ content: Content, dark: Bool, size: CGSize? = nil, scrolledToEnd: Bool = false) async throws -> Data {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        if let size {
            window.frame = CGRect(origin: .zero, size: size)
        }
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await settle()
        if scrolledToEnd {
            await Self.scrollToEnd(window)
        }
        return try Self.image(of: window)
    }

    /// Scrolls every scroll view in the window to its end, so the part of the content that starts below the fold can be looked at.
    static func scrollToEnd(_ window: UIWindow) async {
        for scroll in scrollViews(in: window) where scroll.contentSize.height > scroll.bounds.height {
            let bottom = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        }
        try? await Task.sleep(for: .seconds(1))
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found = (view as? UIScrollView).map { [$0] } ?? []
        found += view.subviews.flatMap { scrollViews(in: $0) }
        return found
    }

    /// The window as a PNG. visionOS has no Liquid Glass in these views and its `drawHierarchy` leaves blank tiles in a window this large, so it renders the layer tree instead; every other platform draws the hierarchy.
    static func image(of window: UIWindow) throws -> Data {
        window.rootViewController?.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            #if os(visionOS)
            window.layer.render(in: context.cgContext)
            #else
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            #endif
        }
        return try #require(image.pngData())
    }

    static func distinctColors(in png: Data) -> Int {
        guard let cgImage = UIImage(data: png)?.cgImage else {
            return 0
        }
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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
}

#endif

#if os(iOS)
extension PaywallSnapshotTests {
    private func present(_ controller: UIViewController) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    private func closeButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityLabel == MidgarCommerceUIStrings.close {
            return button
        }
        return view.subviews.lazy.compactMap { closeButton(in: $0) }.first
    }

    @Test func theUIKitHostCompletesOnceWhenTheCloseButtonIsTapped() async throws {
        let live = try await makeLive()
        let store = live.store
        var results: [MidgarPaywallResult] = []
        let controller = MidgarPaywallViewController(
            configuration: MidgarPaywallConfiguration(
                kind: .subscriptions(groupID: PaywallSnapshotTests.group),
                links: PaywallSnapshotTests.links,
                title: "Go Pro",
                subtitle: "Everything unlocked.",
                systemImage: "sparkles"
            ),
            store: store,
            theme: PaywallSnapshotTests.theme
        ) { results.append($0) }
        let window = try present(controller)
        defer { window.isHidden = true }
        await settle()

        let button = try #require(closeButton(in: controller.view))
        button.sendActions(for: .primaryActionTriggered)
        button.sendActions(for: .primaryActionTriggered)

        #expect(results == [.dismissed])
        try write(Self.image(of: window), name: "uikit-host", dark: false)
        await store.stop()
    }
}
#endif

#if os(macOS)
extension PaywallSnapshotTests {
    static let platformName = "mac"
    static let appearances: [Bool?] = [false, true]

    func render<Content: View>(_ content: Content, dark: Bool, size requested: CGSize? = nil, scrolledToEnd: Bool = false) async throws -> Data {
        let size = requested ?? CGSize(width: 520, height: 760)
        let hosting = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light).frame(width: size.width, height: size.height))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = KeyableWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.appearance = hosting.appearance
        window.setFrameOrigin(CGPoint(x: 80, y: 80))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        await settle()
        window.makeKey()
        try? await Task.sleep(for: .milliseconds(700))
        hosting.layoutSubtreeIfNeeded()
        if let captured = await Self.captureWindow(window, size: size) {
            return captured
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// A borderless window that can become key, so its prominent buttons draw as they do in a window the customer is using instead of in their grey inactive state.
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// Asks the window server for the window's pixels, which includes the layers `cacheDisplay` leaves out (StoreKit's views). `CGWindowListCreateImage` is looked up at run time because the SDK marks it obsolete; an app may still capture its own windows with it without the screen recording permission. Nil when the function is missing.
    static func captureWindow(_ window: NSWindow, size: CGSize) async -> Data? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        let capture = unsafeBitCast(symbol, to: WindowImageFunction.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0
        guard let image = capture(.null, optionIncludingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?.takeRetainedValue() else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func distinctColors(in png: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: png), let bytes = rep.bitmapData else {
            return 0
        }
        var seen = Set<UInt32>()
        for index in Swift.stride(from: 0, to: rep.pixelsWide * rep.pixelsHigh, by: 7) {
            let base = index * rep.samplesPerPixel
            seen.insert(UInt32(bytes[base]) << 16 | UInt32(bytes[base + 1]) << 8 | UInt32(bytes[base + 2]))
            if seen.count > 8 { break }
        }
        return seen.count
    }
}
#endif

/// Last on purpose: a purchase uses up the introductory offer, and the snapshot tests before it show the offer.
extension PaywallSnapshotTests {
    @Test func aPurchaseMadeThroughTheStoreReachesTheEligibilityPolicy() async throws {
        let live = try await makeLive()
        let policy = MidgarTrialPolicy()
        let before = try await policy.presentation(for: Self.yearly)

        #if os(visionOS)
        let scene = try #require(UIApplication.shared.connectedScenes.first)
        let result = try await live.store.purchase(Self.yearly, confirmIn: scene)
        #else
        let result = try await live.store.purchase(Self.yearly)
        #endif
        var after = try await policy.presentation(for: Self.yearly)
        for _ in 0..<10 where after != nil {
            try await Task.sleep(for: .milliseconds(500))
            after = try await policy.presentation(for: Self.yearly)
        }

        #expect(before != nil)
        #expect(result == .purchased)
        #if os(iOS)
        #expect(after == nil)
        #endif
        live.session.resetToDefaultState()
        live.session.clearTransactions()
        await live.store.stop()
    }
}
