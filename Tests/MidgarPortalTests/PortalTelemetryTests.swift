import Foundation
import Testing
import MidgarCore
@testable import MidgarPortal

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Captures what the portal's signals client sends, instead of sending it.
private final class PortalSignalsStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [Data] = []

    static func reset() {
        lock.withLock { bodies = [] }
    }

    static var captured: [Data] {
        lock.withLock { bodies }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "portal-signals.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock { Self.bodies.append(Self.body(of: request)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"accepted":1,"dropped":0}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}

@Suite(.serialized) struct PortalTelemetryTests {
    private func makeSignals(directory: URL) -> MidgarSignals {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortalSignalsStub.self]
        return MidgarSignals(
            configuration: MidgarHTTPConfiguration(
                baseURL: URL(string: "https://portal-signals.test")!,
                appID: "psywave",
                session: URLSession(configuration: configuration)
            ),
            directory: directory
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("portal-signals-\(UUID().uuidString)")
    }

    @Test func everyPortalEventReachesSignalsWithTheNamesAndPropsTheSchemaAccepts() async throws {
        PortalSignalsStub.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let signals = makeSignals(directory: directory)
        let telemetry = Telemetry(config: MidgarConfig(storefront: "FI", placement: "portal"), signals: { signals })

        await telemetry.record(.portalOpen)
        await telemetry.record(.impression, appId: "123")
        await telemetry.record(.tap, appId: "123")
        await telemetry.record(.loaded, appId: "123")
        await telemetry.record(.launch, appId: "123")
        await signals.flush()

        let body = try #require(PortalSignalsStub.captured.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.compactMap { $0["name"] as? String } == ["portal_open", "impression", "tap", "loaded", "launch"])
        let propsByEvent = events.compactMap { $0["props"] as? [String: String] }
        #expect(propsByEvent.first == ["storefront": "fi", "placement": "portal"])
        for props in propsByEvent.dropFirst() {
            #expect(props == ["appId": "123", "storefront": "fi", "placement": "portal"])
        }
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("source"))
        #expect(!text.contains("\"event\""))
    }

    @Test func anOverlayCarriesTheOfferedAppAndTheFeaturePlacement() {
        let telemetry = Telemetry(config: MidgarConfig(storefront: "FI", placement: PortalMoments.placement))
        #expect(telemetry.props(.overlay, appId: "6787493695") == [
            "appId": .string("6787493695"),
            "storefront": .string("fi"),
            "placement": .string("feature"),
        ])
    }

    @MainActor @Test func aMomentThatOffersAnAppReachesSignalsAsAnOverlayEventForThatApp() async throws {
        PortalSignalsStub.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let signals = makeSignals(directory: directory)
        let config = MidgarConfig(storefront: "FI", placement: PortalMoments.placement)
        let host = PortalFixtures.app("psywave", moments: ["export": "flaccy"])
        let flaccy = PortalFixtures.app("flaccy", id: "6787493695")
        let (defaults, cleanup) = PortalFixtures.defaults()
        defer { cleanup() }
        let dependencies = MomentDependencies(
            hostBundleID: host.bundleId,
            catalog: { [host, flaccy] },
            installed: { _ in [] },
            ownedSlugs: { [] },
            history: MomentHistory(defaults: defaults),
            presenter: FakePresenter(),
            inFlight: MomentsInFlight(),
            platform: .ios
        )

        let outcome = await MomentCoordinator.run(
            moment: "export",
            config: config,
            dependencies: dependencies,
            telemetry: Telemetry(config: config, signals: { signals })
        )
        await signals.flush()

        #expect(outcome == .presented(flaccy))
        let body = try #require(PortalSignalsStub.captured.first)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.compactMap { $0["name"] as? String } == ["overlay"])
        #expect(events.first?["props"] as? [String: String] == ["appId": "6787493695", "storefront": "fi", "placement": "feature"])
    }

    @MainActor @Test func aMomentThatOffersNothingSendsNothing() async {
        PortalSignalsStub.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let signals = makeSignals(directory: directory)
        let config = MidgarConfig(placement: PortalMoments.placement)
        let host = PortalFixtures.app("psywave", moments: ["export": "flaccy"])
        let (defaults, cleanup) = PortalFixtures.defaults()
        defer { cleanup() }
        let dependencies = MomentDependencies(
            hostBundleID: host.bundleId,
            catalog: { [host, PortalFixtures.app("flaccy")] },
            installed: { _ in [] },
            ownedSlugs: { ["flaccy"] },
            history: MomentHistory(defaults: defaults),
            presenter: FakePresenter(),
            inFlight: MomentsInFlight(),
            platform: .ios
        )

        let outcome = await MomentCoordinator.run(
            moment: "export",
            config: config,
            dependencies: dependencies,
            telemetry: Telemetry(config: config, signals: { signals })
        )
        await signals.flush()

        #expect(outcome == .skipped(.alreadyOwned))
        #expect(PortalSignalsStub.captured.isEmpty)
    }

    @Test func everyEventThePortalCanSendIsInTheSignalsSchema() throws {
        let schema = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("services/signals/src/schema.ts")
        guard let source = try? String(contentsOf: schema, encoding: .utf8) else { return }
        let all: [MidgarEvent] = [.portalOpen, .impression, .tap, .loaded, .launch, .overlay]
        for event in all {
            let declared = source.contains("\n  \(event.rawValue): {") || source.contains("\n  \"\(event.rawValue)\": {")
            #expect(declared, "signals schema has no event \(event.rawValue)")
        }
    }

    @Test func theStorefrontIsLeftOutWhenTheDeviceHasNone() {
        let telemetry = Telemetry(config: MidgarConfig(storefront: "", placement: "settings"))
        let props = telemetry.props(.tap, appId: "9")
        #expect(props["placement"] == .string("settings"))
        #expect(props["appId"] == .string("9"))
    }

    @Test func portalOpenCarriesNoPromotedApp() {
        let telemetry = Telemetry(config: MidgarConfig(storefront: "us", placement: "entry"))
        #expect(telemetry.props(.portalOpen, appId: "9")["appId"] == nil)
    }

    @Test func disabledTelemetrySendsNothing() async {
        PortalSignalsStub.reset()
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let signals = makeSignals(directory: directory)
        let telemetry = Telemetry(config: MidgarConfig(enableTelemetry: false), signals: { signals })

        await telemetry.record(.tap, appId: "123")
        await signals.flush()

        #expect(await signals.pendingCount == 0)
        #expect(PortalSignalsStub.captured.isEmpty)
    }

    @Test func anUnconfiguredSignalsClientLeavesThePortalWorking() async {
        let telemetry = Telemetry(config: MidgarConfig(), signals: { nil })

        await telemetry.record(.tap, appId: "123")
        telemetry.send(.impression, appId: "123")
    }
}
