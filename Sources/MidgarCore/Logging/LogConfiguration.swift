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

    /// `Library/Logs` on Apple platforms; on Linux, where there is no Library, the XDG state directory's `<process>/logs`
    /// (`~/.local/state/<process>/logs` by default), so logs outlive a reboot instead of landing in the temporary directory.
    static var standardDirectory: URL {
        #if os(Linux)
        return linuxStateDirectory(environment: ProcessInfo.processInfo.environment, processName: ProcessInfo.processInfo.processName)
        #else
        let library = (try? FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return library.appendingPathComponent("Logs", isDirectory: true)
        #endif
    }

    /// `$XDG_STATE_HOME/<process>/logs`, or `~/.local/state/<process>/logs` when it is unset or not absolute.
    static func linuxStateDirectory(environment: [String: String], processName: String) -> URL {
        let home = environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let state = environment["XDG_STATE_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? home.appendingPathComponent(".local/state", isDirectory: true)
        let name = processName.isEmpty ? "app" : processName.lowercased()
        return state.appendingPathComponent(name, isDirectory: true).appendingPathComponent("logs", isDirectory: true)
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
