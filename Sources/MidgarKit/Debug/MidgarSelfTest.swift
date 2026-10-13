#if DEBUG && canImport(UIKit) && !os(tvOS)
import UIKit

/// A scripted run of the portal for devices nobody is touching: it opens the portal, flicks the
/// camera around, records frame pacing, and writes screenshots and a JSON report into the app's
/// Documents folder. Only compiled into Debug builds and only active with `-midgar-selftest`.
public enum MidgarSelfTest {
    @MainActor
    public static func autorun(after delay: TimeInterval = 2.5) {
        guard ProcessInfo.processInfo.arguments.contains("-midgar-selftest") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await run()
        }
    }

    @MainActor
    static func run() async {
        guard let host = Midgar.topViewController() else { return }
        let directory = outputDirectory()
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

        let report = meter.report(
            maxFPS: window.windowScene?.screen.maximumFramesPerSecond ?? 60,
            cells: canvas.controller.layout.cells.count
        )
        write("selftest.json", report, to: directory)
        NSLog("MIDGAR_SELFTEST_DONE \(String(data: report, encoding: .utf8) ?? "")")
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
