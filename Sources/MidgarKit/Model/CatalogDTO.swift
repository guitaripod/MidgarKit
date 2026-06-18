import Foundation

struct CatalogResponse: Codable {
    let version: Int
    let updatedAt: String?
    let developer: CatalogDeveloper?
    let apps: [CatalogEntry]
}

struct CatalogDeveloper: Codable {
    let name: String?
    let artistId: String?
}

struct CatalogEntry: Codable {
    let appId: String
    let bundleId: String
    let name: String
    let tagline: String?
    let genre: String?
    let accent: String?
    let featured: Bool?
    let order: Int?
    let icon: URL?
    let screenshots: [URL]?
}
