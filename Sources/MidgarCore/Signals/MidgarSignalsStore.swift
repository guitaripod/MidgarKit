import Foundation

/// The unsent events on disk, `<directory>/signals-<app>.json`, so they survive a relaunch.
struct MidgarSignalsStore: Sendable {
    let fileURL: URL

    init(directory: URL?, appID: String) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("signals-\(Self.safeName(appID)).json")
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Midgar", isDirectory: true)
    }

    /// The saved events, or none when the file is missing or unreadable. Events are re-checked on the way in, so an edited file cannot queue anything a caller could not.
    func load() -> [MidgarSignalEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([MidgarSignalEvent].self, from: data)
        else {
            return []
        }
        return events.compactMap { MidgarSignalEvent(name: $0.name, props: $0.props) }
    }

    /// Replaces the file with `events`, or removes it when there are none. A disk that refuses only costs the events a relaunch would have restored.
    func save(_ events: [MidgarSignalEvent]) {
        guard !events.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    /// The file of another kind of state for the same app, next to the queue: `signals-<kind>-<app>.json`.
    func sibling(_ kind: String) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent.replacingOccurrences(of: "signals-", with: "signals-\(kind)-"))
    }

    /// Keeps an app id from escaping the directory.
    private static func safeName(_ appID: String) -> String {
        String(appID.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
    }
}
