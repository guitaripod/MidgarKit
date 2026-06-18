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

enum MidgarImageCache {
    nonisolated(unsafe) static let memory: NSCache<NSURL, MidgarImage> = {
        let cache = NSCache<NSURL, MidgarImage>()
        cache.countLimit = 240
        return cache
    }()
}

/// Loads an image through Midgar's cached session, memoizing decoded results. Raw bytes are also
/// retained by the session's on-disk `URLCache`, so artwork survives cold launches.
func midgarLoadImage(_ url: URL?) async -> MidgarImage? {
    guard let url else { return nil }
    if let cached = MidgarImageCache.memory.object(forKey: url as NSURL) { return cached }
    guard let (data, response) = try? await URLSession.midgar.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let image = MidgarImage(data: data)
    else { return nil }
    MidgarImageCache.memory.setObject(image, forKey: url as NSURL)
    return image
}

/// Loads a bundled fallback icon shipped with the package (used for apps not yet on the store index).
func midgarBundledIcon(_ appId: String) -> MidgarImage? {
    guard let url = Bundle.module.url(forResource: appId, withExtension: "png", subdirectory: "fallback-icons"),
          let data = try? Data(contentsOf: url)
    else { return nil }
    return MidgarImage(data: data)
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
