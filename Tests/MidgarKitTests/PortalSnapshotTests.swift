#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import MidgarKit

/// Renders the portal to PNG files for visual review. Does nothing unless
/// `MIDGAR_SNAPSHOT_DIR` points at an output directory.
@MainActor
final class PortalSnapshotTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func canvas(in view: NSView) -> PortalCanvasView? {
        if let found = view as? PortalCanvasView { return found }
        for child in view.subviews {
            if let found = canvas(in: child) { return found }
        }
        return nil
    }

    private func write(_ view: NSView, name: String, to directory: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return XCTFail("no bitmap") }
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    private func run(_ controller: PortalController, from start: CFTimeInterval, seconds: Double) -> CFTimeInterval {
        var time = start
        let end = start + seconds
        while time < end {
            time += 1.0 / 60.0
            controller.tick(now: time)
        }
        return time
    }

    func testRenderPortalStates() throws {
        guard let directory = outputDirectory else { throw XCTSkip("MIDGAR_SNAPSHOT_DIR not set") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let size = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_SIZE"]
            .flatMap { value -> CGSize? in
                let parts = value.split(separator: "x").compactMap { Double($0) }
                return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
            } ?? CGSize(width: 393, height: 852)
        let host = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_HOST"] ?? "com.marcusziade.psywave"

        MidgarPlatform.simulated = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_PLATFORM"].flatMap(MidgarPlatform.init(rawValue:)) ?? .ios
        defer { MidgarPlatform.simulated = nil }
        let model = PortalModel(config: MidgarConfig(enableTelemetry: false), hostBundleID: host)
        let hosting = NSHostingView(rootView: PortalScreen(model: model))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        hosting.frame = CGRect(origin: .zero, size: size)
        spin(0.6)
        let canvasView = try XCTUnwrap(canvas(in: hosting), "canvas view missing")
        let controller = canvasView.controller

        var time: CFTimeInterval = 100
        controller.begin(at: time)
        time = run(controller, from: time, seconds: 0.18)
        spin(0.1)
        try write(hosting, name: "1-intro", to: directory)
        time = run(controller, from: time, seconds: 0.6)
        spin(0.1)
        try write(hosting, name: "2-spreading", to: directory)
        time = run(controller, from: time, seconds: 3)
        spin(0.6)
        time = run(controller, from: time, seconds: 0.5)
        try write(hosting, name: "3-settled", to: directory)

        controller.pointerBegan()
        controller.pointerMoved(translation: CGPoint(x: -150, y: 90))
        time = run(controller, from: time, seconds: 0.1)
        spin(0.1)
        try write(hosting, name: "4-dragging", to: directory)
        controller.pointerEnded(velocity: .zero)
        time = run(controller, from: time, seconds: 2)
        spin(0.4)
        time = run(controller, from: time, seconds: 0.3)
        try write(hosting, name: "5-after-drag", to: directory)

        controller.bringToCentre(controller.layout.core)
        time = run(controller, from: time, seconds: 2)
        spin(0.4)
        time = run(controller, from: time, seconds: 0.3)
        try write(hosting, name: "6-core", to: directory)

        if let outer = controller.layout.cells.last {
            controller.bringToCentre(outer)
            time = run(controller, from: time, seconds: 2)
            spin(0.4)
            time = run(controller, from: time, seconds: 0.3)
            try write(hosting, name: "7-outer", to: directory)
        }
    }

    func testRenderEntryCard() throws {
        guard let directory = outputDirectory else { throw XCTSkip("MIDGAR_SNAPSHOT_DIR not set") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        MidgarPlatform.simulated = .ios
        defer { MidgarPlatform.simulated = nil }
        for width in [360.0, 393.0, 600.0] {
            let card = MidgarEntryView(config: MidgarConfig(enableTelemetry: false))
            let size = CGSize(width: width, height: MidgarEntryView.preferredHeight + 40)
            let container = NSView(frame: CGRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(white: 0.1, alpha: 1).cgColor
            card.frame = CGRect(x: 16, y: 20, width: width - 32, height: MidgarEntryView.preferredHeight)
            container.addSubview(card)
            let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = container
            window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
            window.orderFront(nil)
            spin(0.8)
            try write(container, name: "entry-\(Int(width))", to: directory)
        }
    }
}
#endif
