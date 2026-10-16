import Foundation
import Testing
@testable import MidgarCore

extension MidgarLog.Category {
    static let store = MidgarLog.Category("store")
}

@Suite(.serialized) struct LoggingFacadeTests {
    @Test func everyLevelWritesOneLineToTheConfiguredFile() {
        let directory = Self.install()
        defer { Self.remove(directory) }

        MidgarLog.debug("d-line", category: .store)
        MidgarLog.info("i-line", category: .store)
        MidgarLog.notice("n-line", category: .store)
        MidgarLog.error("e-line", category: .store)
        MidgarLog.fault("f-line", category: .store)
        MidgarLog.flush()

        let text = Self.contents(in: directory)
        #expect(text.contains("[debug ] [store       ] d-line"))
        #expect(text.contains("[info  ] [store       ] i-line"))
        #expect(text.contains("[notice] [store       ] n-line"))
        #expect(text.contains("[error ] [store       ] e-line"))
        #expect(text.contains("[fault ] [store       ] f-line"))
        #expect(text.split(separator: "\n").count == 5)
        #expect(MidgarLog.logFileURLs.map(\.lastPathComponent) == ["probe.log"])
    }

    @Test func appLoggerWarningsTravelAsNotice() {
        let directory = Self.install()
        defer { Self.remove(directory) }

        AppLogger.warning("careful", category: .store)
        AppLogger.error("broken", category: .store)
        MidgarLog.flush()

        let text = Self.contents(in: directory)
        #expect(text.contains("[notice] [store       ] careful"))
        #expect(text.contains("[error ] [store       ] broken"))
    }

    @Test func secretsAreRedactedBeforeTheyReachTheFile() {
        let directory = Self.install()
        defer { Self.remove(directory) }

        MidgarLog.info("auth Bearer abc123def456.ghi789-jkl012", category: .network)
        MidgarLog.flush()

        let text = Self.contents(in: directory)
        #expect(text.contains("auth Bearer [REDACTED]"))
        #expect(!text.contains("abc123def456"))
    }

    private static func install() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggingFacadeTests-\(UUID().uuidString)", isDirectory: true)
        MidgarLog.install(LogConfiguration(
            subsystem: "app.midgar.tests",
            directory: directory,
            fileName: "probe.log",
            maxBytes: 1 << 20,
            keepFiles: 2
        ))
        return directory
    }

    private static func contents(in directory: URL) -> String {
        (try? String(contentsOf: directory.appendingPathComponent("probe.log"), encoding: .utf8)) ?? ""
    }

    private static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
