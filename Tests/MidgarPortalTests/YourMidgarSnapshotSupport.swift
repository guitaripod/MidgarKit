import CoreGraphics
import Foundation
import ImageIO
import Vision
@testable import MidgarPortal

/// What the "Your Midgar" snapshot tests render: a person with Psywave open who has Flaccy (lifetime Pro), Embr and Solar Beam (a subscription in its billing grace period).
enum YourMidgarSnapshotFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func snapshot() -> PortalAccountSnapshot {
        PortalAccountSnapshot(
            appSlugs: ["psywave", "flaccy", "embr", "solar-beam"],
            entitlements: [
                PortalEntitlement(app: "flaccy", entitlement: "pro", kind: "non_consumable"),
                PortalEntitlement(
                    app: "psywave", entitlement: "pro", kind: "subscription",
                    expiresDate: (now.timeIntervalSince1970 + 21 * 86_400) * 1000
                ),
                PortalEntitlement(
                    app: "solar-beam", entitlement: "premium", kind: "subscription",
                    expiresDate: (now.timeIntervalSince1970 - 86_400) * 1000,
                    graceExpiresDate: (now.timeIntervalSince1970 + 5 * 86_400) * 1000,
                    inGracePeriod: true
                ),
            ]
        )
    }

    @MainActor
    static func section(hostBundleID: String, platform: MidgarPlatform) -> YourMidgarSection {
        YourMidgarBuilder.build(
            snapshot: snapshot(),
            catalog: PortalRanking.order(apps: CatalogService.bundledApps(), hostBundleID: hostBundleID, installed: []),
            hostBundleID: hostBundleID,
            installed: ["com.guitaripod.embr"],
            platform: platform,
            now: now
        )!
    }

    /// The lines Vision reads from a PNG, so a render test can check the words are on screen and not only that something was drawn.
    static func recognizedText(in png: Data) -> [String] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Distinct colours among a sample of pixels, to tell a drawn image from a blank one.
    static func distinctColours(in png: Data, limit: Int = 64) -> Int {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return 0 }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var seen = Set<UInt32>()
        for index in stride(from: 0, to: bytes.count, by: 28) {
            seen.insert(UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]))
            if seen.count > limit { break }
        }
        return seen.count
    }
}
