import Foundation

/// The settings one logging runtime is built from. Sizes below one byte and negative archive counts are clamped.
struct LogConfiguration: Sendable {
    static var standard: LogConfiguration {
        LogConfiguration(
            subsystem: Bundle.main.bundleIdentifier ?? "app.midgar",
            directory: standardDirectory,
            fileName: "app.log",
            maxBytes: 2 * 1024 * 1024,
            keepFiles: 3
        )
    }

    static var standardDirectory: URL {
        let library = (try? FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return library.appendingPathComponent("Logs", isDirectory: true)
    }

    let subsystem: String
    let directory: URL
    let fileName: String
    let maxBytes: UInt64
    let keepFiles: Int

    init(subsystem: String, directory: URL, fileName: String, maxBytes: UInt64, keepFiles: Int) {
        self.subsystem = subsystem
        self.directory = directory
        self.fileName = fileName
        self.maxBytes = max(maxBytes, 1)
        self.keepFiles = max(keepFiles, 0)
    }
}
