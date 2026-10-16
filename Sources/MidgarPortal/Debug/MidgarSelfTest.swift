#if DEBUG && canImport(UIKit) && !os(tvOS) && !os(visionOS)
import StoreKit
import UIKit

/// A scripted run of the portal for devices nobody is touching: it opens the portal, flicks the
/// camera around, records frame pacing, and writes screenshots and a JSON report into the app's
/// Documents folder. Only compiled into Debug builds and only active with `-midgar-selftest` or the
/// `MIDGAR_SELFTEST` environment variable.
public enum MidgarSelfTest {
    @MainActor
    public static func autorun(after delay: TimeInterval = 2.5) {
        let info = ProcessInfo.processInfo
        guard info.arguments.contains("-midgar-selftest") || info.environment["MIDGAR_SELFTEST"] != nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await run()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    @MainActor
    static func run() async {
        guard let host = Midgar.topViewController() else { return }
        let directory = outputDirectory()
        if let hostWindow = host.view.window { snapshot(hostWindow, name: "00-settings", to: directory) }
        Midgar.present(from: host, config: MidgarConfig(enableTelemetry: false, placement: "selftest"))
        try? await Task.sleep(nanoseconds: 3_800_000_000)
        guard let window = host.view.window ?? Midgar.topViewController()?.view.window,
              let canvas = findCanvas(in: window) else {
            write("selftest.json", Data("{\"error\":\"canvas not found\"}".utf8), to: directory)
            return
        }
        snapshot(window, name: "01-open", to: directory)

        let meter = FrameMeter()
        meter.start()
        await script(canvas.controller)
        meter.stop()
        snapshot(window, name: "02-after-script", to: directory)

        canvas.controller.bringToCentre(canvas.controller.layout.core)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        snapshot(window, name: "03-core", to: directory)
        if let far = canvas.controller.layout.cells.last {
            canvas.controller.bringToCentre(far)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            snapshot(window, name: "04-outer", to: directory)
        }

        let productSheet = await openProductSheet(canvas.controller, window: window, directory: directory)

        var report = meter.report(
            maxFPS: window.windowScene?.screen.maximumFramesPerSecond ?? 60,
            cells: canvas.controller.layout.cells.count
        )
        if var object = (try? JSONSerialization.jsonObject(with: report)) as? [String: Any] {
            object["productSheetPresented"] = productSheet
            report = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? report
        }
        write("selftest.json", report, to: directory)
        NSLog("MIDGAR_SELFTEST_DONE \(String(data: report, encoding: .utf8) ?? "")")
    }

    /// Centres an app, activates it like a tap would, and reports whether the App Store product
    /// sheet came up inside the app instead of the App Store opening.
    @MainActor
    private static func openProductSheet(_ controller: PortalController, window: UIWindow, directory: URL) async -> Bool {
        guard let cell = controller.layout.cells.first(where: { !$0.isCore }) else { return false }
        controller.bringToCentre(cell)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        controller.activateFocused()
        var presented: UIViewController?
        for _ in 0..<24 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            presented = Midgar.topViewController()
            if isProductSheet(presented) { break }
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        snapshot(window, name: "05-product", to: directory)
        let isSheet = isProductSheet(presented)
        write("product-class.txt", Data(String(describing: presented.map { type(of: $0) }).utf8), to: directory)
        presented?.dismiss(animated: false)
        return isSheet
    }

    /// Recent iOS shows the App Store sheet inside Apple's own service card container instead of
    /// an `SKStoreProductViewController` instance.
    @MainActor
    private static func isProductSheet(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        return controller.isKind(of: SKStoreProductViewController.self)
            || String(describing: type(of: controller)).contains("ServiceCard")
    }

    @MainActor
    private static func script(_ controller: PortalController) async {
        for round in 0..<3 {
            controller.pointerBegan()
            let sign: CGFloat = round.isMultiple(of: 2) ? -1 : 1
            for step in 0..<45 {
                controller.pointerMoved(translation: CGPoint(x: sign * CGFloat(step) * 4.5, y: CGFloat(step) * 2.2))
                try? await Task.sleep(nanoseconds: 11_000_000)
            }
            controller.pointerEnded(velocity: CGPoint(x: sign * 1100, y: 420))
            try? await Task.sleep(nanoseconds: 1_400_000_000)
        }
    }

    @MainActor
    private static func findCanvas(in view: UIView) -> PortalCanvasView? {
        if let canvas = view as? PortalCanvasView { return canvas }
        for child in view.subviews {
            if let found = findCanvas(in: child) { return found }
        }
        return nil
    }

    private static func outputDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("midgar-selftest", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private static func snapshot(_ window: UIWindow, name: String, to directory: URL) {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() { write("\(name).png", data, to: directory) }
    }

    private static func write(_ name: String, _ data: Data, to directory: URL) {
        try? data.write(to: directory.appendingPathComponent(name))
    }
}

@MainActor
private final class FrameMeter: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var intervals: [Double] = []

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if last > 0 { intervals.append((link.timestamp - last) * 1000) }
        last = link.timestamp
    }

    func report(maxFPS: Int, cells: Int) -> Data {
        let sorted = intervals.sorted()
        let count = max(sorted.count, 1)
        let mean = sorted.reduce(0, +) / Double(count)
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let p99 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        let budget = 1000.0 / Double(maxFPS)
        let slow = sorted.filter { $0 > budget * 1.5 }.count
        let object: [String: Any] = [
            "frames": sorted.count,
            "meanMs": mean,
            "p95Ms": p95,
            "p99Ms": p99,
            "worstMs": sorted.last ?? 0,
            "budgetMs": budget,
            "slowFrames": slow,
            "maxFPS": maxFPS,
            "cells": cells,
            "thermal": ProcessInfo.processInfo.thermalState.rawValue,
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
#endif
