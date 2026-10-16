#if canImport(CryptoKit)
import Foundation
import Testing
@testable import MidgarCore

@Suite struct ConfigCacheTests {
    @Test func cacheRoundTripsAcrossStores() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        let jws = try fixture.signer.jws(version: 40, values: ["limit": 6], kill: ["ai"])
        fixture.host.enqueue([fixture.ok(jws)])

        _ = await fixture.store().refresh()
        #expect(try String(contentsOf: fixture.cacheFile, encoding: .utf8) == jws)

        let relaunched = fixture.store(defaults: ["limit": 3])
        #expect(relaunched.current.version == 40)
        #expect(relaunched.current.int("limit", default: 0) == 6)
        #expect(relaunched.current.isKilled("ai"))
    }

    @Test func relaunchedStoreSendsETagAndKeepsFloor() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 40)),
            .json(304, ""),
            fixture.ok(try fixture.signer.jws(version: 39))
        ])

        _ = await fixture.store().refresh()
        let relaunched = fixture.store()
        #expect(await relaunched.refresh() == .unchanged)
        #expect(fixture.host.requests.last?.headers["If-None-Match"] == "\"40\"")
        #expect(await relaunched.refresh(force: true) == .rejected(.rolledBack(version: 39, lastGood: 40)))
    }

    @Test func tamperedCacheFileIsIgnored() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        let jws = try fixture.signer.jws(version: 40, values: ["limit": 6])
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let forged = try fixture.signer.jws(version: 41, values: ["limit": 999])
        let parts = jws.split(separator: ".").map(String.init)
        let swapped = [parts[0], forged.split(separator: ".").map(String.init)[1], parts[2]].joined(separator: ".")
        try swapped.write(to: fixture.cacheFile, atomically: true, encoding: .utf8)

        let store = fixture.store(defaults: ["limit": 3])

        #expect(store.current.version == nil)
        #expect(store.current.int("limit", default: 0) == 3)
        #expect(fixture.logs.lines.contains { $0.contains("cache ignored") })
    }

    @Test func cacheSignedByAnotherKeyOrAppIsIgnored() throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)

        try ConfigSigner().jws().write(to: fixture.cacheFile, atomically: true, encoding: .utf8)
        #expect(fixture.store().current.version == nil)

        try fixture.signer.jws(app: "psywave").write(to: fixture.cacheFile, atomically: true, encoding: .utf8)
        #expect(fixture.store().current.version == nil)

        try "not a jws".write(to: fixture.cacheFile, atomically: true, encoding: .utf8)
        #expect(fixture.store().current.version == nil)
    }

    @Test func deletingTheCacheFileDoesNotLowerTheFloor() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 40, kill: ["ai"])),
            fixture.ok(try fixture.signer.jws(version: 39))
        ])
        _ = await fixture.store().refresh()
        try FileManager.default.removeItem(at: fixture.cacheFile)

        let relaunched = fixture.store()
        let result = await relaunched.refresh()

        #expect(result == .rejected(.rolledBack(version: 39, lastGood: 40)))
        #expect(relaunched.current.version == nil)
    }

    @Test func aCacheFileSwappedForAnOlderDocumentIsIgnored() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([fixture.ok(try fixture.signer.jws(version: 40, kill: ["ai"]))])
        _ = await fixture.store().refresh()
        try fixture.signer.jws(version: 30).write(to: fixture.cacheFile, atomically: true, encoding: .utf8)

        let relaunched = fixture.store()

        #expect(relaunched.current.version == nil)
        #expect(fixture.logs.lines.contains { $0.contains("cache ignored: rolledBack") })
    }

    @Test func theFloorLivesPerSlugInItsOwnDefaults() {
        let suite = "midgar-floor-test-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)
        let first = MidgarConfigFloor(defaults: defaults, slug: "solar-beam")
        let other = MidgarConfigFloor(defaults: defaults, slug: "psywave")

        first.raise(to: 12)
        first.raise(to: 5)

        #expect(first.version == 12)
        #expect(other.version == 0)
    }

    @Test func defaultCacheDirectoryIsApplicationSupportMidgar() {
        let url = MidgarConfigCache(directory: nil, slug: "solar-beam").fileURL
        #expect(url.lastPathComponent == "config-solar-beam.jws")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Midgar")
    }

    @Test func slugCannotEscapeTheDirectory() {
        let directory = URL(fileURLWithPath: "/tmp/midgar-cache")
        let url = MidgarConfigCache(directory: directory, slug: "../evil/x").fileURL
        #expect(url.deletingLastPathComponent().path == directory.path)
    }
}
#endif
