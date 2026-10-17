#if os(iOS)
import SwiftUI
import UIKit
import XCTest
@testable import MidgarPortal

/// Renders the portal with "Your Midgar" open at iPhone and iPad sizes and writes the PNGs to `MIDGAR_SNAPSHOT_DIR` when it is set.
@MainActor
final class YourMidgarSnapshotTestsIOS: XCTestCase {
    private struct Device {
        let name: String
        let size: CGSize
        let safeArea: UIEdgeInsets
    }

    private let iPhone = Device(name: "iphone", size: CGSize(width: 393, height: 852), safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))
    private let iPad = Device(name: "ipad", size: CGSize(width: 820, height: 1180), safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0))

    func testYourMidgarOnIPhone() async throws {
        try await render(iPhone)
    }

    func testYourMidgarOnIPad() async throws {
        try await render(iPad)
    }

    private func render(_ device: Device) async throws {
        MidgarPlatform.simulated = .ios
        defer { MidgarPlatform.simulated = nil }
        let snapshot = YourMidgarSnapshotFixtures.snapshot()
        let model = PortalModel(
            config: MidgarConfig(enableTelemetry: false),
            hostBundleID: "com.marcusziade.psywave",
            account: PortalAccount(source: FakeAccountSource(slugs: .success(snapshot.appSlugs ?? []), entitlements: .success(snapshot.entitlements ?? [])))
        )
        let window = UIWindow(frame: CGRect(origin: .zero, size: device.size))
        window.overrideUserInterfaceStyle = .dark
        let controller = UIHostingController(rootView: PortalScreen(model: model))
        controller.additionalSafeAreaInsets = device.safeArea
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            model.stop()
        }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<200 where model.yourMidgar == nil { try await Task.sleep(for: .milliseconds(25)) }
        let section = try XCTUnwrap(model.yourMidgar)
        XCTAssertEqual(section.yours.first?.app.slug, "psywave")
        model.showYourMidgar()
        try await Task.sleep(for: .seconds(2))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        replaceGlass(in: window)

        let image = UIGraphicsImageRenderer(size: device.size).image { context in
            window.layer.render(in: context.cgContext)
        }
        let data = try XCTUnwrap(image.pngData())
        try save(data, name: "your-midgar-\(device.name)")

        XCTAssertGreaterThan(YourMidgarSnapshotFixtures.distinctColours(in: data), 8)
        let text = YourMidgarSnapshotFixtures.recognizedText(in: data).joined(separator: "\n")
        XCTAssertTrue(text.contains("Your Midgar"), text)
        XCTAssertTrue(text.contains("Lifetime"), text)
    }

    /// `CALayer.render(in:)` draws nothing once a Liquid Glass layer (`CASDFLayer`) is in the tree, so the glass is hidden and a translucent shape of the same frame stands in for it. The material itself cannot be captured here.
    private func replaceGlass(in window: UIWindow) {
        var standIns: [(host: CALayer, frame: CGRect)] = []
        func visit(_ layer: CALayer) {
            let name = String(describing: type(of: layer))
            if name == "CASDFLayer" {
                layer.isHidden = true
            } else if name == "SDFLayer", let host = layer.superlayer {
                standIns.append((host, layer.frame))
                layer.sublayers?.forEach(visit)
            } else {
                layer.sublayers?.forEach(visit)
            }
        }
        visit(window.layer)
        for (host, frame) in standIns {
            let shape = CALayer()
            shape.frame = frame
            shape.cornerRadius = frame.height <= 60 ? frame.height / 2 : 30
            shape.backgroundColor = UIColor(white: 1, alpha: 0.13).cgColor
            shape.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
            shape.borderWidth = 1
            host.insertSublayer(shape, at: 0)
        }
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
