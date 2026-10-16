import Foundation

struct ITunesLookupResponse: Decodable {
    let results: [ITunesApp]
}

struct ITunesApp: Decodable {
    let trackId: Int
    let artistId: Int?
    let bundleId: String?
    let trackName: String?
    let primaryGenreName: String?
    let formattedPrice: String?
    let averageUserRating: Double?
    let userRatingCount: Int?
    let artworkUrl512: URL?
    let artworkUrl100: URL?
    let screenshotUrls: [URL]?
    let ipadScreenshotUrls: [URL]?
}
