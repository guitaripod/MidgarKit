import Foundation

/// The screens of one run, oldest first, and when the last was marked.
struct MidgarTrailSnapshot: Sendable, Equatable, Codable {
    var screens: [String]
    var at: Date
}

/// The last twenty screens a person passed through, kept so a crash report can say where it happened.
///
/// An app marks a screen or an action by an id from its own list in the registry (`[lifestream] screens`), for example `MidgarTrail.mark("player")`. The trail stays on the device: it is read only when the system reports a crash of the run it belongs to, and then travels inside that one crash card, where the server reads any id outside the app's list as `other`. Nothing is kept while usage counts are off.
public enum MidgarTrail {
    static let capacity = 20

    /// Notes that the person reached a screen or did an action. `screen` is a lowercase id of at most 40 letters, digits and underscores; anything else is ignored.
    public static func mark(_ screen: String) {
        guard isScreenID(screen) else {
            return
        }
        guard MidgarSignals.isEnabled else {
            MidgarTrailStore.shared.clear()
            return
        }
        MidgarTrailStore.shared.mark(screen, at: Date())
    }

    /// The trail of the run before this one, as it stood when that run ended, or nil when it left none.
    static func previousRun() -> MidgarTrailSnapshot? {
        MidgarTrailStore.shared.previous
    }

    static func isScreenID(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-z0-9_]{0,39}$"#, options: .regularExpression) != nil
    }
}

/// The trail's ring and its file. The file holds the current run's trail and is rewritten on every mark, off the caller's thread, so a crash leaves the last screens behind for the next launch to read. The lock guards the ring, which is what makes the unchecked conformance sound.
final class MidgarTrailStore: @unchecked Sendable {
    static let shared = MidgarTrailStore(fileURL: MidgarSignalsStore.defaultDirectory.appendingPathComponent("trail.json"))

    private let fileURL: URL
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "cc.midgarcorp.trail", qos: .utility)
    private var ring: [String] = []
    private let loaded: MidgarTrailSnapshot?

    /// Reads what the last run left in the file before this run writes to it.
    init(fileURL: URL) {
        self.fileURL = fileURL
        loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(MidgarTrailSnapshot.self, from: $0) }
    }

    var previous: MidgarTrailSnapshot? {
        loaded
    }

    var current: [String] {
        lock.withLock { ring }
    }

    func mark(_ screen: String, at moment: Date) {
        let snapshot = lock.withLock {
            ring.append(screen)
            if ring.count > MidgarTrail.capacity {
                ring.removeFirst(ring.count - MidgarTrail.capacity)
            }
            return MidgarTrailSnapshot(screens: ring, at: moment)
        }
        let url = fileURL
        writer.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    /// Forgets this run's trail and removes the file.
    func clear() {
        lock.withLock { ring.removeAll() }
        let url = fileURL
        writer.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Waits for the writes queued so far. Tests use it to read the file.
    func waitForWrites() {
        writer.sync {}
    }
}
