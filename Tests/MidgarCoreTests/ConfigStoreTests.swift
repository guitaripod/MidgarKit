#if canImport(CryptoKit)
import Foundation
import Testing
@testable import MidgarCore

@Suite struct ConfigStoreTests {
    @Test func validDocumentApplies() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([fixture.ok(try fixture.signer.jws(version: 10, values: ["limit": 7], kill: ["ai"]))])
        let store = fixture.store(defaults: ["limit": 3, "other": true])

        #expect(store.current.int("limit", default: 0) == 3)
        let result = await store.refresh()

        #expect(result == .updated(version: 10))
        #expect(store.current.int("limit", default: 0) == 7)
        #expect(store.current.bool("other", default: false))
        #expect(store.current.isKilled("ai"))
        #expect(store.current.version == 10)
        let sent = try #require(fixture.host.requests.first)
        #expect(sent.url.path == "/v1/config/\(configTestSlug)")
        #expect(sent.headers["If-None-Match"] == nil)
    }

    @Test func badSignatureKeepsLastGood() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        let good = try fixture.signer.jws(version: 10, values: ["limit": 7])
        let forged = try ConfigSigner(kid: configTestKid).jws(version: 11, values: ["limit": 99])
        fixture.host.enqueue([fixture.ok(good), fixture.ok(forged)])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        #expect(result == .rejected(.badSignature))
        #expect(store.current.int("limit", default: 0) == 7)
        #expect(store.current.version == 10)
        #expect(fixture.logs.lines.contains { $0.contains("badSignature") })
        #expect(!fixture.logs.lines.contains { $0.contains(forged) || $0.contains(good) })
    }

    @Test func unknownKidAndOtherAppAreRejected() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(headerKid: "other")),
            fixture.ok(try fixture.signer.jws(app: "psywave"))
        ])
        let store = fixture.store(defaults: ["limit": 3])

        #expect(await store.refresh() == .rejected(.unknownKey))
        #expect(await store.refresh(force: true) == .rejected(.wrongApp))
        #expect(store.current.version == nil)
        #expect(store.current.int("limit", default: 0) == 3)
    }

    @Test func lowerVersionIsRejected() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 20, values: ["limit": 7])),
            fixture.ok(try fixture.signer.jws(version: 19, values: ["limit": 1]))
        ])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        #expect(result == .rejected(.rolledBack(version: 19, lastGood: 20)))
        #expect(store.current.int("limit", default: 0) == 7)
    }

    @Test func equalVersionIsANoOp() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 20, values: ["limit": 7])),
            fixture.ok(try fixture.signer.jws(version: 20, values: ["limit": 8]))
        ])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        #expect(result == .unchanged)
        #expect(store.current.int("limit", default: 0) == 7)
    }

    @Test func notModifiedKeepsCurrentAndSendsETag() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 1_800_000_000, values: ["limit": 7])),
            .json(304, "")
        ])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        #expect(result == .unchanged)
        #expect(store.current.int("limit", default: 0) == 7)
        #expect(fixture.host.requests.last?.headers["If-None-Match"] == "\"1800000000\"")
    }

    @Test func noConfigKeepsTheLastGoodDocumentAndItsKillSwitches() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        let good = try fixture.signer.jws(version: 20, values: ["limit": 7], kill: ["uploads"])
        let older = try fixture.signer.jws(version: 5, values: ["limit": 1])
        fixture.host.enqueue([
            fixture.ok(good),
            .json(404, "{\"error\":{\"code\":\"no_config\",\"message\":\"none\"}}"),
            fixture.ok(older)
        ])
        let store = fixture.store(defaults: ["limit": 3])

        _ = await store.refresh()
        #expect(await store.refresh(force: true) == .noConfig)
        #expect(store.current.version == 20)
        #expect(store.current.int("limit", default: 0) == 7)
        #expect(store.current.isKilled("uploads"))
        #expect(FileManager.default.fileExists(atPath: fixture.cacheFile.path))

        #expect(await store.refresh(force: true) == .rejected(.rolledBack(version: 5, lastGood: 20)))
        #expect(store.current.version == 20)
        #expect(fixture.host.requests[2].headers["If-None-Match"] == "\"20\"")
    }

    @Test func noConfigWithoutDocumentStaysOnDefaults() async {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([.json(404, "{\"error\":{\"code\":\"no_config\",\"message\":\"none\"}}")])
        let store = fixture.store(defaults: ["limit": 3])

        #expect(await store.refresh() == .noConfig)
        #expect(store.current.int("limit", default: 0) == 3)
    }

    @Test func offlineKeepsLastGood() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 20, values: ["limit": 7])),
            .failing(.notConnectedToInternet), .failing(.notConnectedToInternet), .failing(.notConnectedToInternet)
        ])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        #expect(result == .failed(.offline))
        #expect(store.current.int("limit", default: 0) == 7)
    }

    @Test func serverErrorKeepsLastGood() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 20, values: ["limit": 7])),
            .json(500, "{\"error\":{\"code\":\"boom\",\"message\":\"x\"}}")
        ])
        let store = fixture.store()

        _ = await store.refresh()
        let result = await store.refresh(force: true)

        guard case .failed(.server(let status, _, _)) = result else {
            Issue.record("expected a server failure, got \(result)")
            return
        }
        #expect(status == 500)
        #expect(store.current.version == 20)
    }

    @Test func minimumIntervalThrottlesUnlessForced() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([
            fixture.ok(try fixture.signer.jws(version: 20)),
            .json(304, ""), .json(304, ""), .json(304, "")
        ])
        let store = fixture.store(interval: 900)

        _ = await store.refresh()
        #expect(await store.refresh() == .throttled)
        fixture.clock.advance(by: 899)
        #expect(await store.refresh() == .throttled)
        #expect(fixture.host.requests.count == 1)
        fixture.clock.advance(by: 2)
        #expect(await store.refresh() == .unchanged)
        #expect(await store.refresh(force: true) == .unchanged)
        #expect(fixture.host.requests.count == 3)
    }

    @Test func failedRefreshDoesNotStartTheInterval() async {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([.failing(.notConnectedToInternet), .failing(.notConnectedToInternet), .failing(.notConnectedToInternet)])
        let store = fixture.store()

        #expect(await store.refresh() == .failed(.offline))
        #expect(await store.refresh() != .throttled)
    }

    @Test func updatesStreamReportsChanges() async throws {
        let fixture = ConfigFixture()
        defer { fixture.cleanUp() }
        fixture.host.enqueue([fixture.ok(try fixture.signer.jws(version: 30, values: ["limit": 4]))])
        let store = fixture.store()
        var changes = store.updates().makeAsyncIterator()

        _ = await store.refresh()
        let change = await changes.next()

        #expect(change?.version == 30)
        #expect(change?.int("limit", default: 0) == 4)
    }
}
#endif
