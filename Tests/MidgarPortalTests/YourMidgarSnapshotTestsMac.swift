#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import MidgarPortal

/// Renders the portal with "Your Midgar" open on the Mac and writes the PNG to `MIDGAR_SNAPSHOT_DIR` when it is set.
@MainActor
final class YourMidgarSnapshotTestsMac: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func render(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    func testYourMidgarOnTheMacPortal() async throws {
        MidgarPlatform.simulated = .mac
        defer { MidgarPlatform.simulated = nil }
        let host = "com.midgarcorp.flaccy.mac"
        let source = FakeAccountSource(
            slugs: .success(YourMidgarSnapshotFixtures.snapshot().appSlugs ?? []),
            entitlements: .success(YourMidgarSnapshotFixtures.snapshot().entitlements ?? [])
        )
        let model = PortalModel(config: MidgarConfig(enableTelemetry: false), hostBundleID: host, account: PortalAccount(source: source))
        let hosting = NSHostingView(rootView: PortalScreen(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 780, height: 700)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -6000, y: -6000))
        window.orderFront(nil)
        spin(0.5)
        for _ in 0..<200 where model.yourMidgar == nil { try await Task.sleep(for: .milliseconds(25)) }
        let section = try XCTUnwrap(model.yourMidgar)
        XCTAssertEqual(section.yours.first?.app.slug, "flaccy")
        model.showYourMidgar()
        try await Task.sleep(for: .seconds(2))
        let data = try render(hosting)
        window.orderOut(nil)
        model.stop()
        try save(data, name: "your-midgar-mac")

        XCTAssertGreaterThan(YourMidgarSnapshotFixtures.distinctColours(in: data), 8)
        let text = YourMidgarSnapshotFixtures.recognizedText(in: data).joined(separator: "\n")
        XCTAssertTrue(text.contains("Your Midgar"), text)
        XCTAssertTrue(text.contains("Lifetime"), text)
    }
}
#endif
