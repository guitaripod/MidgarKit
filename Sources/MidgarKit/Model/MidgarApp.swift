import Foundation

/// A single app shown in the Midgar storefront, after the curated catalog has been merged with
/// live App Store data for the user's region.
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

    public var id: String { appId }

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
            return "GET"
        }
        return price
    }

    /// First grapheme of the name, used for the monogram fallback when no artwork loads.
    public var monogram: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}
