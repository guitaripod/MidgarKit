import Foundation

/// One experiment as the app's remote config delivers it: the versions it compares, the event that puts an install in it and the event that counts as its outcome.
struct MidgarExperiment: Sendable, Equatable {
    /// The config keys that carry experiments start with this; the rest of the key is the experiment's id.
    static let keyPrefix = "lab."

    let id: String
    let variants: [String]
    let exposed: String
    let converted: String

    /// Reads `control,outcome;paywall.view;paywall.purchase`, the form `midgar lab config` writes. Nil for anything else, so a malformed value runs no experiment.
    init?(id: String, value: String) {
        let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !id.isEmpty else {
            return nil
        }
        let variants = parts[0].split(separator: ",").map(String.init)
        guard variants.count >= 2, Set(variants).count == variants.count, !parts[1].isEmpty, !parts[2].isEmpty, parts[1] != parts[2] else {
            return nil
        }
        self.id = id
        self.variants = variants
        self.exposed = parts[1]
        self.converted = parts[2]
    }

    /// Every experiment a config snapshot carries, by id.
    static func all(in config: MidgarConfig) -> [MidgarExperiment] {
        config.strings(withPrefix: keyPrefix)
            .compactMap { MidgarExperiment(id: $0.key, value: $0.value) }
            .sorted { $0.id < $1.id }
    }

    /// The version an install with this seed is in: the seed and the experiment's id hashed together, so one install lands in unrelated versions of unrelated experiments and always in the same version of one.
    func variant(seed: UInt64) -> String {
        variants[Int(Self.hash("\(seed):\(id)") % UInt64(variants.count))]
    }

    /// FNV-1a over the text, the same in every launch (Swift's own hashing is seeded per process), then mixed. FNV's lowest bit is only the parity of the bytes' lowest bits, so without the mixing an install's versions in two experiments of two versions each would always match or always differ.
    static func hash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        hash = (hash ^ (hash >> 30)) &* 0xbf58_476d_1ce4_e5b9
        hash = (hash ^ (hash >> 27)) &* 0x94d0_49bb_1331_11eb
        return hash ^ (hash >> 31)
    }
}

/// What an install keeps for the lab, `<directory>/signals-lab-<app>.json`: the random seed that picks its versions, which never leaves the device, and the experiments it was already exposed to, so an outcome only counts after an exposure.
struct MidgarLabState: Codable, Sendable, Equatable {
    var seed: UInt64
    var exposed: [String] = []
}

/// The lab's state for one app, shared by the signals actor and the views that ask which version to show. Every field is touched only under `lock`, which is what makes the unchecked conformance sound.
final class MidgarLab: @unchecked Sendable {
    private let fileURL: URL
    private let makeSeed: @Sendable () -> UInt64
    private let lock = NSLock()
    private var state: MidgarLabState?
    private var forced: [String: String] = [:]

    init(store: MidgarSignalsStore, makeSeed: @escaping @Sendable () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        fileURL = store.sibling("lab")
        self.makeSeed = makeSeed
    }

    /// The version of an experiment this install is in: a forced one when a debug screen set it, else the one its seed picks.
    func variant(of experiment: MidgarExperiment) -> String {
        lock.withLock {
            if let forced = forced[experiment.id], experiment.variants.contains(forced) {
                return forced
            }
            return experiment.variant(seed: loaded().seed)
        }
    }

    /// Shows one version on this install whatever its seed says, until the process ends. For a debug screen and for review on a TestFlight build.
    func force(_ variant: String?, for experiment: String) {
        lock.withLock { forced[experiment] = variant }
    }

    /// Records that the install saw the experiment. Returns whether it is the first time.
    func markExposed(_ experiment: String) -> Bool {
        lock.withLock {
            var current = loaded()
            guard !current.exposed.contains(experiment) else {
                return false
            }
            current.exposed.append(experiment)
            save(current)
            return true
        }
    }

    /// Whether the install saw the experiment before.
    func wasExposed(_ experiment: String) -> Bool {
        lock.withLock { loaded().exposed.contains(experiment) }
    }

    /// Forgets the seed and the exposures, when the person turns usage counts off.
    func forget() {
        lock.withLock {
            state = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// The state from disk, or a new one with a fresh seed that is written at once: losing the seed would move the install to other versions.
    private func loaded() -> MidgarLabState {
        if let state {
            return state
        }
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(MidgarLabState.self, from: data) {
            state = saved
            return saved
        }
        let fresh = MidgarLabState(seed: makeSeed())
        save(fresh)
        return fresh
    }

    private func save(_ next: MidgarLabState) {
        state = next
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
