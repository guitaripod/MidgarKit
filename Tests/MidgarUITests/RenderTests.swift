#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import MidgarUI

@Suite @MainActor struct RenderTests {
    private let size = CGSize(width: 390, height: 640)
    private let tallSize = CGSize(width: 390, height: 1500)

    private func render<Content: View>(_ content: Content, dark: Bool, name: String, size: CGSize? = nil) throws -> Data {
        let size = size ?? self.size
        let themed = content
            .midgarTheme(MidgarTheme(accent: MidgarColor(hex: 0x2A9D8F)))
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: size.width, height: size.height)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try dump(data, name: name, dark: dark)
        return data
    }

    private func dump(_ data: Data, name: String, dark: Bool) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    private func distinctPixelCount(_ png: Data) -> Int {
        guard let rep = NSBitmapImageRep(data: png), let bytes = rep.bitmapData else { return 0 }
        var seen = Set<UInt32>()
        let count = rep.pixelsWide * rep.pixelsHigh
        let stride = rep.samplesPerPixel
        for index in Swift.stride(from: 0, to: count, by: 7) {
            let base = index * stride
            seen.insert(UInt32(bytes[base]) << 16 | UInt32(bytes[base + 1]) << 8 | UInt32(bytes[base + 2]))
            if seen.count > 8 { break }
        }
        return seen.count
    }

    private func check<Content: View>(_ name: String, _ content: Content, tall: Bool = false) throws {
        let light = try render(content, dark: false, name: name, size: tall ? tallSize : nil)
        let dark = try render(content, dark: true, name: name, size: tall ? tallSize : nil)
        #expect(distinctPixelCount(light) > 2, "\(name) light rendered blank")
        #expect(distinctPixelCount(dark) > 2, "\(name) dark rendered blank")
        #expect(light != dark, "\(name) looks the same in light and dark")
    }

    @Test func settingsRenders() throws {
        try check("settings", RenderFixtures.settings())
    }

    @Test func usageCountsRenders() async throws {
        try check("usage-counts", try await RenderFixtures.usageCounts(), tall: true)
    }

    @Test func usageCountsRendersWithoutNumbers() throws {
        try check("usage-counts-no-numbers", RenderFixtures.usageCountsWithoutNumbers(), tall: true)
    }

    @Test func onboardingRenders() throws {
        try check("onboarding", RenderFixtures.onboarding())
    }

    @Test func whatsNewRenders() throws {
        try check("whats-new", RenderFixtures.whatsNew())
    }

    @Test func toastRenders() throws {
        for style in MidgarToast.Style.allCases {
            try check("toast-\(style)", RenderFixtures.toast(style))
        }
    }
}
#endif
