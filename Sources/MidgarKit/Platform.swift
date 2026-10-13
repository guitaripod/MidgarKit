import Foundation

#if canImport(UIKit)
import UIKit
public typealias MidgarColor = UIColor
typealias MidgarImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias MidgarColor = NSColor
typealias MidgarImage = NSImage
#endif

import CoreGraphics
import ImageIO

enum MidgarImageCache {
    /// Bounded by decoded byte cost rather than object count. App Store screenshots are ~1290×2796;
    /// a count-based limit of a few hundred such images would reserve gigabytes of bitmaps.
    nonisolated(unsafe) static let memory: NSCache<NSString, MidgarImage> = {
        let cache = NSCache<NSString, MidgarImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)|\(Int(maxPixel))" as NSString
    }
}

/// Decodes `data` straight to a thumbnail no larger than `maxPixel` points on its longest edge.
///
/// `UIImage(data:)` keeps the image at full resolution and defers the decode until the layer is
/// first rendered — which happens on the main thread mid-scroll. Going through ImageIO with
/// `kCGImageSourceShouldCacheImmediately` forces the decode here, on whatever background executor
/// is running the enclosing async call, and produces a bitmap sized for the view instead of for
/// the source file.
private func midgarDownsample(_ data: Data, maxPixel: CGFloat, scale: CGFloat) -> MidgarImage? {
    guard maxPixel > 0,
          let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }

    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: Int((maxPixel * scale).rounded()),
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return nil
    }
    #if canImport(UIKit)
    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    #else
    // `NSImage.size` is in points; the thumbnail comes back in pixels, so it has to be divided
    // by the backing scale or the artwork draws at twice its intended size on Retina.
    let points = NSSize(
        width: CGFloat(cgImage.width) / scale,
        height: CGFloat(cgImage.height) / scale
    )
    return NSImage(cgImage: cgImage, size: points)
    #endif
}

/// Carries a decoded image off the background executor. `NSImage` only gained a `Sendable`
/// conformance in macOS 14 and the package supports 13; the images boxed here are freshly created
/// from an immutable `CGImage` and never mutated, so the unchecked conformance is sound.
private struct MidgarImageBox: @unchecked Sendable {
    let image: MidgarImage
}

private func midgarDecodedCost(_ image: MidgarImage) -> Int {
    #if canImport(UIKit)
    guard let cgImage = image.cgImage else { return 1 }
    #else
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
    #endif
    return max(1, cgImage.bytesPerRow * cgImage.height)
}

/// Coalesces concurrent requests for the same artwork. Every call site is already on the main
/// actor, so a plain dictionary of in-flight tasks is enough — without it, fast scrolling starts a
/// fresh download per cell for artwork that is already being fetched.
@MainActor
private enum MidgarImageLoader {
    static var inFlight: [NSString: Task<MidgarImageBox?, Never>] = [:]

    static func load(_ url: URL, maxPixel: CGFloat, scale: CGFloat) async -> MidgarImage? {
        let key = MidgarImageCache.key(url, maxPixel)
        if let cached = MidgarImageCache.memory.object(forKey: key) { return cached }
        if let existing = inFlight[key] { return await existing.value?.image }

        let task = Task<MidgarImageBox?, Never>.detached(priority: .userInitiated) {
            guard let (data, response) = try? await URLSession.midgar.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = midgarDownsample(data, maxPixel: maxPixel, scale: scale)
            else { return nil }
            MidgarImageCache.memory.setObject(image, forKey: key, cost: midgarDecodedCost(image))
            return MidgarImageBox(image: image)
        }
        inFlight[key] = task
        let boxed = await task.value
        inFlight[key] = nil
        return boxed?.image
    }
}

/// Loads artwork through Midgar's cached session, downsampled to `maxPixel` points on its longest
/// edge. Raw bytes are retained by the session's on-disk `URLCache`, so artwork survives cold
/// launches; decoded thumbnails are memoized in a byte-bounded memory cache.
@MainActor
func midgarLoadImage(_ url: URL?, maxPixel: CGFloat, scale: CGFloat) async -> MidgarImage? {
    guard let url else { return nil }
    return await MidgarImageLoader.load(url, maxPixel: maxPixel, scale: scale)
}

/// Loads a bundled fallback icon shipped with the package (used for apps not yet on the store
/// index). Reads and decodes off the main thread — this is synchronous file I/O.
func midgarBundledIcon(_ appId: String, maxPixel: CGFloat, scale: CGFloat) async -> MidgarImage? {
    guard let url = Bundle.module.url(
        forResource: appId, withExtension: "png", subdirectory: "fallback-icons")
    else { return nil }
    let boxed = await Task.detached(priority: .userInitiated) { () -> MidgarImageBox? in
        guard let data = try? Data(contentsOf: url),
              let image = midgarDownsample(data, maxPixel: maxPixel, scale: scale)
        else { return nil }
        return MidgarImageBox(image: image)
    }.value
    return boxed?.image
}

/// Parses a hex color string into sRGB components in `0...1`. Free function so it can be unit-tested
/// without comparing opaque color values.
func midgarRGBA(hex: String?) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard var string = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased(),
          string.count == 6 || string.count == 8,
          string.allSatisfy({ $0.isHexDigit })
    else { return nil }

    if string.count == 6 { string += "FF" }
    guard let value = UInt32(string, radix: 16) else { return nil }
    return (
        r: CGFloat((value >> 24) & 0xFF) / 255,
        g: CGFloat((value >> 16) & 0xFF) / 255,
        b: CGFloat((value >> 8) & 0xFF) / 255,
        a: CGFloat(value & 0xFF) / 255
    )
}

extension MidgarColor {
    /// Creates a color from a `#RRGGBB` or `#RRGGBBAA` hex string. Returns `nil` for malformed input.
    convenience init?(hex: String?) {
        guard let c = midgarRGBA(hex: hex) else { return nil }
        #if canImport(UIKit)
        self.init(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        #else
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        #endif
    }
}

func midgarCGImage(of image: MidgarImage) -> CGImage? {
    #if canImport(UIKit)
    return image.cgImage
    #else
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    #endif
}

/// Loads artwork as a `CGImage`, downsampled to `maxPixel` points, for the portal's textures.
@MainActor
func midgarLoadCGImage(_ url: URL?, maxPixel: CGFloat, scale: CGFloat) async -> CGImage? {
    guard let image = await midgarLoadImage(url, maxPixel: maxPixel, scale: scale) else { return nil }
    return midgarCGImage(of: image)
}

func midgarBundledCGImage(_ appId: String, maxPixel: CGFloat, scale: CGFloat) async -> CGImage? {
    guard let image = await midgarBundledIcon(appId, maxPixel: maxPixel, scale: scale) else { return nil }
    return midgarCGImage(of: image)
}
