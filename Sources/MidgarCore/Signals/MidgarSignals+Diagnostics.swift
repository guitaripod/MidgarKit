import Foundation

/// The body of `POST /v1/signals/diagnostics`.
struct MidgarCrashCardBatch: Encodable, Sendable {
    let cards: [MidgarCrashCard]
}

/// The crash cards waiting to be sent and the faults already taken today.
struct MidgarDiagnosticsState: Codable, Sendable, Equatable {
    var day = ""
    var taken: [String] = []
    var pending: [MidgarCrashCard] = []
}

/// `<directory>/signals-diagnostics-<app>.json`, next to the event queue, so a card made while offline goes out after the next launch.
struct MidgarDiagnosticsStore: Sendable {
    let fileURL: URL

    func load() -> MidgarDiagnosticsState {
        guard let data = try? Data(contentsOf: fileURL), let state = try? JSONDecoder().decode(MidgarDiagnosticsState.self, from: data) else {
            return MidgarDiagnosticsState()
        }
        return state
    }

    /// Replaces the file, or removes it when nothing is worth keeping.
    func save(_ state: MidgarDiagnosticsState) {
        guard state != MidgarDiagnosticsState() else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }
}

extension MidgarSignals {
    /// The most cards one install sends in a day, so an app that crashes in a loop reports the loop once.
    static let dailyCardLimit = 5
    static let cardsPerRequest = 5

    var diagnosticsStore: MidgarDiagnosticsStore {
        MidgarDiagnosticsStore(fileURL: store.sibling("diagnostics"))
    }

    /// Turns the JSON of one MetricKit diagnostic payload into crash cards and sends them. A fault already taken today is not taken again, at most five are taken in a day, and what cannot be sent now waits on disk for the next launch. While usage counts are off, killed, or this is a TestFlight or development install, nothing is kept and nothing is sent.
    ///
    /// - Parameters:
    ///   - data: `MXDiagnosticPayload.jsonRepresentation()`.
    ///   - appBinaries: The names of the binaries that ship inside the app.
    ///   - trail: The trail of the run before this launch.
    func recordDiagnosticJSON(_ data: Data, appBinaries: Set<String>, trail: MidgarTrailSnapshot?) async {
        let cards = MidgarCrashCards.cards(fromDiagnosticJSON: data, appBinaries: appBinaries, trail: trail)
        guard !cards.isEmpty else {
            return
        }
        guard !isSuppressed else {
            diagnosticsStore.save(MidgarDiagnosticsState())
            return
        }
        var state = diagnosticsStore.load()
        let today = Self.dayKey(now())
        if state.day != today {
            state.day = today
            state.taken = []
        }
        for card in cards {
            let key = Self.stableHash(card.key)
            guard state.taken.count < Self.dailyCardLimit, !state.taken.contains(key) else {
                continue
            }
            state.taken.append(key)
            state.pending.append(card)
        }
        diagnosticsStore.save(state)
        await sendPendingCards()
    }

    /// Sends the cards that wait on disk, five to a request, and forgets the ones the server took or refused for good. A request that could not be made leaves the rest for the next launch.
    func sendPendingCards() async {
        var state = diagnosticsStore.load()
        guard !state.pending.isEmpty else {
            return
        }
        guard !isSuppressed else {
            diagnosticsStore.save(MidgarDiagnosticsState())
            return
        }
        while !state.pending.isEmpty {
            let batch = Array(state.pending.prefix(Self.cardsPerRequest))
            guard await deliverCards(batch) else {
                break
            }
            state.pending.removeFirst(batch.count)
            diagnosticsStore.save(isSuppressed ? MidgarDiagnosticsState() : state)
        }
    }

    /// What an app's launch does for diagnostics: sends the cards an earlier run could not, and on the platforms that have MetricKit subscribes to it, so crashes, freezes and the day's launch and memory figures arrive without the app asking. Does nothing outside an app's own process.
    func startDiagnostics() async {
        guard MidgarSignalsPlatform.isApp() else {
            return
        }
        await sendPendingCards()
        #if canImport(MetricKit) && (os(iOS) || os(macOS))
        startCollectingMetrics()
        #endif
    }

    /// The UTC calendar day of a moment, `YYYY-MM-DD`.
    static func dayKey(_ moment: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: moment)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// A short hash of a card's key that is the same in every launch (Swift's own hashing is seeded per process): FNV-1a over its bytes, in hex.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
