import Foundation

/// An Apple platform an app can be installed on.
public enum MidgarPlatform: String, Codable, Sendable, CaseIterable {
    case ios
    case mac
    case tvos
    case vision

    nonisolated(unsafe) static var simulated: MidgarPlatform?

    /// The platform the package is compiled for.
    public static var current: MidgarPlatform {
        if let simulated { return simulated }
        #if os(macOS)
        return .mac
        #elseif os(tvOS)
        return .tvos
        #elseif os(visionOS)
        return .vision
        #else
        return .ios
        #endif
    }

    /// Short label for the badge shown on apps that cannot be installed on this device.
    public var badgeLabel: String {
        switch self {
        case .ios: return "iPhone"
        case .mac: return "Mac"
        case .tvos: return "Apple TV"
        case .vision: return "Vision Pro"
        }
    }
}

/// A single app shown in the Midgar portal, after the curated catalog has been merged with live
/// App Store data for the user's region.
public struct MidgarApp: Identifiable, Hashable, Codable, Sendable {
    public let appId: String
    public let bundleId: String
    public let name: String
    public let tagline: String?
    public let genre: String?
    public let accentHex: String?
    public let featured: Bool
    public let order: Int
    public let iconURL: URL?
    public let screenshotURLs: [URL]
    public let rating: Double?
    public let ratingCount: Int?
    public let formattedPrice: String?
    public let platforms: [MidgarPlatform]
    public let topics: [String]
    public let related: [String]
    public let family: String?
    public let value: Double

    public var id: String { appId }

    public init(
        appId: String,
        bundleId: String,
        name: String,
        tagline: String? = nil,
        genre: String? = nil,
        accentHex: String? = nil,
        featured: Bool = false,
        order: Int = 999,
        iconURL: URL? = nil,
        screenshotURLs: [URL] = [],
        rating: Double? = nil,
        ratingCount: Int? = nil,
        formattedPrice: String? = nil,
        platforms: [MidgarPlatform] = [.ios],
        topics: [String] = [],
        related: [String] = [],
        family: String? = nil,
        value: Double = 0.5
    ) {
        self.appId = appId
        self.bundleId = bundleId
        self.name = name
        self.tagline = tagline
        self.genre = genre
        self.accentHex = accentHex
        self.featured = featured
        self.order = order
        self.iconURL = iconURL
        self.screenshotURLs = screenshotURLs
        self.rating = rating
        self.ratingCount = ratingCount
        self.formattedPrice = formattedPrice
        self.platforms = platforms
        self.topics = topics
        self.related = related
        self.family = family
        self.value = value
    }

    /// Public App Store product page, used as a fallback when in-app presentation is unavailable.
    public var storeURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appId)")!
    }

    /// `true` when the App Store reports a usable rating to display.
    public var hasRating: Bool {
        (ratingCount ?? 0) > 0 && (rating ?? 0) > 0
    }

    /// Price label for the GET pill: `nil`/`"Free"` collapse to "GET".
    public var priceLabel: String {
        guard let price = formattedPrice, !price.isEmpty,
              price.caseInsensitiveCompare("Free") != .orderedSame else {
            return MidgarStrings.get
        }
        return price
    }

    /// First grapheme of the name, used for the monogram fallback when no artwork loads.
    public var monogram: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// The URL scheme this app registers so sibling apps can detect and open it: its bundle
    /// identifier, lowercased.
    public var urlScheme: String { bundleId.lowercased() }

    /// `true` when the app can be installed on the platform the package is running on.
    public var runsOnThisDevice: Bool { platforms.contains(.current) }

    /// The platform to name on the badge when the app cannot be installed here.
    public var foreignPlatform: MidgarPlatform? {
        runsOnThisDevice ? nil : platforms.first
    }

    /// The product name without the marketing suffix after the first colon or dash.
    public var shortName: String {
        let separators = CharacterSet(charactersIn: ":—–")
        let head = name.components(separatedBy: separators).first ?? name
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case appId, bundleId, name, tagline, genre, accentHex, featured, order, iconURL
        case screenshotURLs, rating, ratingCount, formattedPrice, platforms, topics, related
        case family, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appId: try container.decode(String.self, forKey: .appId),
            bundleId: try container.decode(String.self, forKey: .bundleId),
            name: try container.decode(String.self, forKey: .name),
            tagline: try container.decodeIfPresent(String.self, forKey: .tagline),
            genre: try container.decodeIfPresent(String.self, forKey: .genre),
            accentHex: try container.decodeIfPresent(String.self, forKey: .accentHex),
            featured: try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false,
            order: try container.decodeIfPresent(Int.self, forKey: .order) ?? 999,
            iconURL: try container.decodeIfPresent(URL.self, forKey: .iconURL),
            screenshotURLs: try container.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? [],
            rating: try container.decodeIfPresent(Double.self, forKey: .rating),
            ratingCount: try container.decodeIfPresent(Int.self, forKey: .ratingCount),
            formattedPrice: try container.decodeIfPresent(String.self, forKey: .formattedPrice),
            platforms: try container.decodeIfPresent([MidgarPlatform].self, forKey: .platforms) ?? [.ios],
            topics: try container.decodeIfPresent([String].self, forKey: .topics) ?? [],
            related: try container.decodeIfPresent([String].self, forKey: .related) ?? [],
            family: try container.decodeIfPresent(String.self, forKey: .family),
            value: try container.decodeIfPresent(Double.self, forKey: .value) ?? 0.5
        )
    }
}
