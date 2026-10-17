import Foundation

/// A signed transaction waiting for the ledger to acknowledge it.
struct PendingReport: Codable, Sendable, Equatable {
    let transactionID: UInt64
    let productID: String
    let signedTransaction: String
    let queuedAt: Date
}

/// The ledger's last answer with the Midgar ID and environment it was for.
struct LedgerSnapshot: Codable, Sendable, Equatable {
    let midgarId: String
    let environment: String
    let fetchedAt: Date
    let entitlements: [LedgerEntitlement]
}

/// Everything the store keeps on disk.
struct CommerceState: Codable, Sendable, Equatable {
    var pending: [PendingReport] = []
    var ledger: LedgerSnapshot?
}

/// `<directory>/commerce-<app>.json`, rewritten atomically after every change so a relaunch resumes the queue and the cache.
struct CommerceStorage: Sendable {
    let fileURL: URL

    init(directory: URL?, appID: String) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("commerce-\(Self.safeName(appID)).json")
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Midgar", isDirectory: true)
    }

    /// The saved state, or an empty one when the file is missing or unreadable.
    func load() -> CommerceState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(CommerceState.self, from: data)
        else {
            return CommerceState()
        }
        return state
    }

    /// Replaces the file. Returns false when the disk refused, so the caller can log that a relaunch would lose the queue.
    @discardableResult
    func save(_ state: CommerceState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Keeps an app id from escaping the directory.
    private static func safeName(_ appID: String) -> String {
        String(appID.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
    }
}
