import Foundation

/// What the offer policy remembers between launches.
public struct MidgarOfferState: Codable, Sendable, Equatable {
    /// How many value moments the app reported.
    public var valueMoments: Int
    /// The value-moment count when the app last offered.
    public var valueMomentsAtLastOffer: Int
    /// How many times the app offered the paywall on its own.
    public var offers: Int
    /// When the app last offered.
    public var lastOffer: Date?
    /// Whether the person owns the offer.
    public var owned: Bool

    public init(valueMoments: Int = 0, valueMomentsAtLastOffer: Int = 0, offers: Int = 0, lastOffer: Date? = nil, owned: Bool = false) {
        self.valueMoments = valueMoments
        self.valueMomentsAtLastOffer = valueMomentsAtLastOffer
        self.offers = offers
        self.lastOffer = lastOffer
        self.owned = owned
    }
}

/// Where the offer policy keeps its state. The app passes its own to put the state in an app group or a test double.
public protocol MidgarOfferStorage: Sendable {
    func load() -> MidgarOfferState
    /// Returns false when the state could not be written, which only means the next launch forgets this change.
    @discardableResult
    func save(_ state: MidgarOfferState) -> Bool
}

/// `<directory>/offer-<app>.json`, rewritten atomically after every change. The directory defaults to `<Application Support>/Midgar`, beside the commerce state.
public struct MidgarOfferFileStorage: MidgarOfferStorage {
    public let fileURL: URL

    public init(appID: String, directory: URL? = nil) {
        let base = directory ?? CommerceStorage.defaultDirectory
        fileURL = base.appendingPathComponent("offer-\(Self.safeName(appID)).json")
    }

    /// The saved state, or an empty one when the file is missing or unreadable.
    public func load() -> MidgarOfferState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? Self.decoder.decode(MidgarOfferState.self, from: data)
        else {
            return MidgarOfferState()
        }
        return state
    }

    @discardableResult
    public func save(_ state: MidgarOfferState) -> Bool {
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
