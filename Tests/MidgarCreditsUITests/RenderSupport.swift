import SwiftUI
import Testing
import MidgarUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Where rendered PNGs go when `MIDGAR_SNAPSHOT_DIR` is set, so a person can look at them.
enum PaywallSnapshotSink {
    static func write(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else {
            return
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name))
    }
}

let paywallTestTheme = MidgarTheme(accent: MidgarColor(hex: 0x2A9D8F))

#if os(macOS)
/// Renders a SwiftUI view to PNG data in an off-screen window in the given appearance.
@MainActor
func renderPaywallPart<Content: View>(_ content: Content, size: CGSize, dark: Bool) throws -> Data {
    let themed = content
        .midgarTheme(paywallTestTheme)
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(width: size.width, height: size.height)
        .background(paywallTestTheme.background.color)
    let hosting = NSHostingView(rootView: themed)
    hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    hosting.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.appearance = hosting.appearance
    window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    hosting.layoutSubtreeIfNeeded()
    let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    return try #require(rep.representation(using: .png, properties: [:]))
}

/// How many different colors the PNG holds, up to nine, to tell a drawn view from a blank one.
func distinctColors(in png: Data) -> Int {
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
#elseif os(iOS)
/// Renders a SwiftUI view to PNG data from its layer tree in a window that is never shown. A package test has no app scene, so `drawHierarchy` would capture nothing.
@MainActor
func renderPaywallPart<Content: View>(_ content: Content, size: CGSize, dark: Bool) throws -> Data {
    let style: UIUserInterfaceStyle = dark ? .dark : .light
    let controller = UIHostingController(rootView: content.midgarTheme(paywallTestTheme).background(paywallTestTheme.background.color))
    controller.overrideUserInterfaceStyle = style
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.overrideUserInterfaceStyle = style
    window.rootViewController = controller
    window.isHidden = false
    defer { window.isHidden = true }
    controller.view.frame = window.bounds
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(size: size).image { context in
        window.layer.render(in: context.cgContext)
    }
    return try #require(image.pngData())
}

func distinctColors(in png: Data) -> Int {
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
#endif
