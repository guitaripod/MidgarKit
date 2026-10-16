import Foundation

/// Appends formatted lines to one size-rotated file, in the order they were appended.
///
/// The file handle and the byte count are read and written only on `queue`, a serial queue, so the writer is safe to share across threads even though it is a class with mutable state.
final class LogFileWriter: @unchecked Sendable {
    let currentURL: URL

    private let directory: URL
    private let fileName: String
    private let maxBytes: UInt64
    private let keepFiles: Int
    private let processID = ProcessInfo.processInfo.processIdentifier
    private let queue = DispatchQueue(label: "app.midgar.MidgarLog.writer", qos: .utility)
    private let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private var handle: FileHandle?
    private var currentSize: UInt64 = 0

    init(directory: URL, fileName: String, maxBytes: UInt64, keepFiles: Int) {
        self.directory = directory
        self.fileName = fileName
        self.maxBytes = maxBytes
        self.keepFiles = keepFiles
        currentURL = directory.appendingPathComponent(fileName)
    }

    func append(_ record: LogRecord) {
        queue.async { [self] in
            write(record)
        }
    }

    /// Blocks until every line appended so far has been written and synced.
    func flush() {
        queue.sync { [self] in
            syncHandle()
        }
    }

    func existingFileURLs() -> [URL] {
        let candidates = [currentURL] + (0..<keepFiles).map { archiveURL(index: $0 + 1) }
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func write(_ record: LogRecord) {
        let line = record.line(timestamp: timestamps.string(from: record.date), processID: processID)
        let data = Data(line.utf8)
        if currentSize > 0, currentSize + UInt64(data.count) > maxBytes {
            rotate()
        }
        guard let openedHandle = openHandle(), (try? openedHandle.write(contentsOf: data)) != nil else {
            return
        }
        currentSize += UInt64(data.count)
        if record.level != .debug {
            try? openedHandle.synchronize()
        }
    }

    private func syncHandle() {
        try? handle?.synchronize()
    }

    private func openHandle() -> FileHandle? {
        if let handle {
            return handle
        }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: currentURL.path), !manager.createFile(atPath: currentURL.path, contents: nil) {
            return nil
        }
        guard let opened = try? FileHandle(forWritingTo: currentURL) else {
            return nil
        }
        currentSize = (try? opened.seekToEnd()) ?? 0
        handle = opened
        return opened
    }

    /// Shifts `name.N.ext` to `name.N+1.ext`, drops the oldest archive and moves the current file to `name.1.ext`. With no archives kept, the current file is simply removed.
    private func rotate() {
        try? handle?.close()
        handle = nil
        currentSize = 0
        let manager = FileManager.default
        guard keepFiles > 0 else {
            try? manager.removeItem(at: currentURL)
            return
        }
        try? manager.removeItem(at: archiveURL(index: keepFiles))
        for index in stride(from: keepFiles - 1, through: 1, by: -1) {
            try? manager.moveItem(at: archiveURL(index: index), to: archiveURL(index: index + 1))
        }
        try? manager.moveItem(at: currentURL, to: archiveURL(index: 1))
    }

    private func archiveURL(index: Int) -> URL {
        let name = fileName as NSString
        let stem = name.deletingPathExtension
        let extensionName = name.pathExtension
        let archiveName = extensionName.isEmpty ? "\(stem).\(index)" : "\(stem).\(index).\(extensionName)"
        return directory.appendingPathComponent(archiveName)
    }
}
