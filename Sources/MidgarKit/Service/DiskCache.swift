import Foundation

/// Persists the last good catalog and the last fully-enriched snapshot so the storefront paints
/// instantly on launch and remains useful entirely offline.
struct DiskCache {
    private let directory: URL
    private let fileManager = FileManager.default

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        directory = base.appendingPathComponent("Midgar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
    private var catalogURL: URL { directory.appendingPathComponent("catalog.json") }

    func loadSnapshot() -> [MidgarApp] {
        decode([MidgarApp].self, from: snapshotURL) ?? []
    }

    func saveSnapshot(_ apps: [MidgarApp]) {
        encode(apps, to: snapshotURL)
    }

    func loadCatalog() -> CatalogResponse? {
        decode(CatalogResponse.self, from: catalogURL)
    }

    func saveCatalog(_ catalog: CatalogResponse) {
        encode(catalog, to: catalogURL)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
