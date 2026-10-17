import Foundation

/// What the review policy remembers between launches.
public struct MidgarReviewState: Codable, Sendable, Equatable {
    /// When the policy first ran in this install, the stand-in for the install date.
    public var firstLaunch: Date?
    /// How many sessions the app reported with ``MidgarReviewPolicy/beginSession()``.
    public var sessions: Int
    /// When the app last asked StoreKit for a review.
    public var lastPrompt: Date?
    /// The app version that was running at the last prompt.
    public var lastPromptedVersion: String?
    /// When the app last reported a purchase that failed.
    public var lastPurchaseFailure: Date?
    /// When the app last reported a refund.
    public var lastRefund: Date?

    public init(
        firstLaunch: Date? = nil,
        sessions: Int = 0,
        lastPrompt: Date? = nil,
        lastPromptedVersion: String? = nil,
        lastPurchaseFailure: Date? = nil,
        lastRefund: Date? = nil
    ) {
        self.firstLaunch = firstLaunch
        self.sessions = sessions
        self.lastPrompt = lastPrompt
        self.lastPromptedVersion = lastPromptedVersion
        self.lastPurchaseFailure = lastPurchaseFailure
        self.lastRefund = lastRefund
    }
}

/// Where the review policy keeps its state. The app passes its own to put the state in an app group or a test double.
public protocol MidgarReviewStorage: Sendable {
    func load() -> MidgarReviewState
    /// Returns false when the state could not be written, which only means the next launch forgets this change.
    @discardableResult
    func save(_ state: MidgarReviewState) -> Bool
}

/// `<directory>/review-<app>.json`, rewritten atomically after every change. The directory defaults to `<Application Support>/Midgar`, beside the commerce state.
public struct MidgarReviewFileStorage: MidgarReviewStorage {
    public let fileURL: URL

    public init(appID: String, directory: URL? = nil) {
        let base = directory ?? CommerceStorage.defaultDirectory
        fileURL = base.appendingPathComponent("review-\(Self.safeName(appID)).json")
    }

    /// The saved state, or an empty one when the file is missing or unreadable.
    public func load() -> MidgarReviewState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? Self.decoder.decode(MidgarReviewState.self, from: data)
        else {
            return MidgarReviewState()
        }
        return state
    }

    @discardableResult
    public func save(_ state: MidgarReviewState) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Keeps an app id from escaping the directory.
    private static func safeName(_ appID: String) -> String {
        String(appID.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
    }
}
