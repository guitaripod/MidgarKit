import Foundation
import MidgarCommerce

/// A paid and finished credit pack purchase that mako has not confirmed yet.
struct PendingCredit: Codable, Sendable, Equatable {
    let packID: String
    let receipt: MidgarPurchaseReceipt
    let queuedAt: Date
}

/// `<directory>/credits-<app>.json`, rewritten atomically after every change so a relaunch resumes the queue. StoreKit finishes a consumable before mako hears of it, so this file is the only local record that a pack was paid for and not yet credited.
struct CreditsPendingStore: Sendable {
    let fileURL: URL

    init(directory: URL?, appID: String) {
        let base = directory ?? Self.defaultDirectory
        fileURL = base.appendingPathComponent("credits-\(Self.safeName(appID)).json")
    }

    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Midgar", isDirectory: true)
    }

    /// The saved queue, or an empty one when the file is missing or unreadable.
    func load() -> [PendingCredit] {
        guard let data = try? Data(contentsOf: fileURL),
              let pending = try? JSONDecoder().decode([PendingCredit].self, from: data)
        else {
            return []
        }
        return pending
    }

    /// Replaces the file. Returns false when the disk refused, so the caller can log that a relaunch would lose the queue.
    @discardableResult
    func save(_ pending: [PendingCredit]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pending).write(to: fileURL, options: .atomic)
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
