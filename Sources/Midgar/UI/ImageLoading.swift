import UIKit

enum MidgarImageCache {
    nonisolated(unsafe) static let memory: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 240
        return cache
    }()
}

/// Loads an image through Midgar's cached session, memoizing decoded results. Raw bytes are also
/// retained by the session's on-disk `URLCache`, so artwork survives cold launches.
func midgarLoadImage(_ url: URL?) async -> UIImage? {
    guard let url else { return nil }
    if let cached = MidgarImageCache.memory.object(forKey: url as NSURL) { return cached }
    guard let (data, response) = try? await URLSession.midgar.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let image = UIImage(data: data)
    else { return nil }
    MidgarImageCache.memory.setObject(image, forKey: url as NSURL)
    return image
}

/// Loads a bundled fallback icon shipped with the package (used for apps not yet on the store index).
func midgarBundledIcon(_ appId: String) -> UIImage? {
    guard let url = Bundle.module.url(forResource: appId, withExtension: "png", subdirectory: "fallback-icons"),
          let data = try? Data(contentsOf: url)
    else { return nil }
    return UIImage(data: data)
}
