import Foundation

/// The last-good JWS on disk, `<directory>/config-<slug>.jws`. It is plain text from the server, so every read is verified again before use.
struct MidgarConfigCache: Sendable {
    let fileURL: URL

    init(directory: URL?, slug: String) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("config-\(Self.safeName(slug)).jws")
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Midgar", isDirectory: true)
    }

    func read() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Writes atomically, creating the directory. Returns false when the disk refused, which only costs the offline fallback.
    @discardableResult
    func write(_ jws: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(jws.utf8).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Keeps a slug from escaping the cache directory.
    private static func safeName(_ slug: String) -> String {
        String(slug.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
    }
}
