#if os(iOS) || os(tvOS)
import UIKit
import XCTest
@testable import MidgarPortal

/// Renders the UIKit portal on a phone held both ways, on an iPad and on a television, checks the words of the
/// header and the card are on screen and that the card clears the canvas's centre, and writes the
/// PNGs to `MIDGAR_SNAPSHOT_DIR` when it is set.
@MainActor
final class PortalLayoutSnapshotTests: XCTestCase {
    private struct Device {
        let name: String
        let size: CGSize
        let safeArea: UIEdgeInsets
        var platform: MidgarPlatform = .ios
    }

    #if os(tvOS)
    func testTelevision() async throws {
        try await render(Device(name: "tv", size: CGSize(width: 1920, height: 1080), safeArea: .zero, platform: .tvos))
    }
    #else
    func testPhonePortrait() async throws {
        try await render(Device(name: "phone-portrait", size: CGSize(width: 375, height: 812), safeArea: UIEdgeInsets(top: 44, left: 0, bottom: 34, right: 0)))
    }

    func testPhoneLandscapePutsTheCardBesideTheCanvas() async throws {
        try await render(Device(name: "phone-landscape", size: CGSize(width: 812, height: 375), safeArea: UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)))
    }

    func testPadLandscape() async throws {
        try await render(Device(name: "pad-landscape", size: CGSize(width: 1194, height: 834), safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)))
    }
    #endif

    private func render(_ device: Device) async throws {
        MidgarPlatform.simulated = device.platform
        defer { MidgarPlatform.simulated = nil }
        let model = PortalModel(config: MidgarConfig(enableTelemetry: false), hostBundleID: "com.marcusziade.psywave")
        let window = UIWindow(frame: CGRect(origin: .zero, size: device.size))
        let controller = MidgarPortalViewController(model: model)
        controller.additionalSafeAreaInsets = device.safeArea
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            model.stop()
        }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .seconds(3))
        controller.view.layoutIfNeeded()
        PortalGlassStandIn.replaceGlass(in: window)

        let card = try XCTUnwrap(find(PortalCardView.self, in: controller.view))
        let canvas = try XCTUnwrap(find(PortalCanvasView.self, in: controller.view))
        let focused = try XCTUnwrap(canvas.controller.frame(forCell: canvas.controller.focusedIndex))
        let cardFrame = card.convert(card.bounds, to: controller.view)
        XCTAssertFalse(cardFrame.contains(focused.center), "the focused icon sits under the card")
        for index in canvas.controller.layout.cells.indices {
            guard let cell = canvas.controller.frame(forCell: index), cell.depth > 0.6 else { continue }
            let icon = CGRect(x: cell.center.x - cell.radius, y: cell.center.y - cell.radius, width: cell.radius * 2, height: cell.radius * 2)
            XCTAssertFalse(icon.intersects(cardFrame), "a near icon at \(icon) runs under the card at \(cardFrame)")
        }
        XCTAssertGreaterThan(cardFrame.width, 200)
        if device.size.width > device.size.height && device.size.height < 560 {
            XCTAssertGreaterThan(cardFrame.midX, device.size.width / 2, "a short, wide screen puts the card beside the canvas")
            XCTAssertLessThan(cardFrame.maxY, device.size.height - device.safeArea.bottom, "the side card stays inside the safe area")
        }

        let image = UIGraphicsImageRenderer(size: device.size).image { context in
            window.layer.render(in: context.cgContext)
        }
        let data = try XCTUnwrap(image.pngData())
        try save(data, name: "portal-\(device.name)")
        let text = YourMidgarSnapshotFixtures.recognizedText(in: data).joined(separator: "\n")
        XCTAssertTrue(text.contains("Midgar"), text)
        XCTAssertTrue(text.contains("You have"), text)
        let title = try XCTUnwrap(card.current?.title)
        XCTAssertTrue(text.contains(title), "\(title) missing from: \(text)")
        XCTAssertGreaterThan(YourMidgarSnapshotFixtures.distinctColours(in: data), 8)
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

@MainActor
enum PortalGlassStandIn {
    /// `CALayer.render(in:)` draws nothing once a Liquid Glass layer (`CASDFLayer`) is in the tree, so the glass is hidden and a translucent shape of the same frame stands in for it. The material itself cannot be captured here.
    static func replaceGlass(in window: UIWindow) {
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
}
#endif
