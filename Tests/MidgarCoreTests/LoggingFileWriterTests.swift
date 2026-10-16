import Foundation
import Testing
@testable import MidgarCore

@Suite struct LoggingFileWriterTests {
    @Test func lineCarriesTimestampProcessLevelCategoryAndMessage() {
        let record = LogRecord(date: Date(timeIntervalSince1970: 0), level: .notice, category: "store", message: "bought")
        let line = record.line(timestamp: "2026-10-16T13:41:02.123Z", processID: 42)
        #expect(line == "2026-10-16T13:41:02.123Z [42] [notice] [store       ] bought\n")
    }

    @Test func lineEscapesBreaksAndKeepsLongCategoriesWhole() {
        let record = LogRecord(date: Date(), level: .info, category: "subscriptions-sync", message: "first\nsecond\r")
        let line = record.line(timestamp: "T", processID: 1)
        #expect(line == "T [1] [info  ] [subscriptions-sync] first\\nsecond\\r\n")
    }

    @Test func flushMakesAppendedLinesVisibleOnDisk() {
        let (writer, directory) = Self.makeWriter(maxBytes: 4096, keepFiles: 1)
        defer { Self.remove(directory) }

        writer.append(Self.record("hello world"))
        writer.flush()

        #expect(Self.contents(of: writer.currentURL).contains("hello world"))
    }

    @Test func rotationShiftsArchivesAndDropsTheOldest() {
        let (writer, directory) = Self.makeWriter(maxBytes: 300, keepFiles: 2)
        defer { Self.remove(directory) }

        for index in 0..<40 {
            writer.append(Self.record("entry \(index) padded so each line is long"))
        }
        writer.flush()

        let files = writer.existingFileURLs()
        #expect(files.map(\.lastPathComponent) == ["app.log", "app.1.log", "app.2.log"])
        for file in files {
            #expect(Self.size(of: file) <= 300)
        }
        let combined = files.reversed().map(Self.contents(of:)).joined()
        #expect(!combined.contains("entry 0 "))
        #expect(combined.contains("entry 39 "))
        let indexes = combined.split(separator: "\n").compactMap { line in
            line.components(separatedBy: "entry ").last?.split(separator: " ").first.flatMap { Int($0) }
        }
        #expect(indexes.count > 0)
        #expect(indexes == indexes.sorted())
    }

    @Test func zeroKeptArchivesTruncatesInsteadOfArchiving() {
        let (writer, directory) = Self.makeWriter(maxBytes: 200, keepFiles: 0)
        defer { Self.remove(directory) }

        for index in 0..<20 {
            writer.append(Self.record("truncate probe \(index)"))
        }
        writer.flush()

        #expect(writer.existingFileURLs().map(\.lastPathComponent) == ["app.log"])
        #expect(Self.size(of: writer.currentURL) <= 200)
    }

    @Test func concurrentAppendsStayInOrderPerSource() async {
        let (writer, directory) = Self.makeWriter(maxBytes: 50_000_000, keepFiles: 0)
        defer { Self.remove(directory) }

        await withTaskGroup(of: Void.self) { group in
            for source in 0..<8 {
                group.addTask {
                    for index in 0..<250 {
                        writer.append(Self.record("source \(source) line \(index)"))
                    }
                }
            }
        }
        writer.flush()

        let lines = Self.contents(of: writer.currentURL).split(separator: "\n")
        #expect(lines.count == 2000)
        for source in 0..<8 {
            let indexes = lines.compactMap { line -> Int? in
                guard line.contains("source \(source) line ") else {
                    return nil
                }
                return line.components(separatedBy: "line ").last.flatMap { Int($0) }
            }
            #expect(indexes == Array(0..<250))
        }
    }

    private static func makeWriter(maxBytes: UInt64, keepFiles: Int) -> (LogFileWriter, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggingFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        let writer = LogFileWriter(directory: directory, fileName: "app.log", maxBytes: maxBytes, keepFiles: keepFiles)
        return (writer, directory)
    }

    private static func record(_ message: String) -> LogRecord {
        LogRecord(date: Date(), level: .info, category: "test", message: message)
    }

    private static func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func size(of url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? UInt64 ?? 0
    }

    private static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
