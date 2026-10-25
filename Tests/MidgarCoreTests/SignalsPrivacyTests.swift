import Foundation
import Testing
@testable import MidgarCore

@Suite struct SignalsPrivacyTests {
    @Test func aRequestCarriesNoAuthorizationEvenWhenTheConfigurationHasATokenProvider() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals(tokenProvider: { "secret-midgar-token" })
        await signals.record("app.launch")

        await signals.flush()

        let request = try #require(harness.host.requests.first)
        #expect(request.headers["Authorization"] == nil)
        #expect(request.headers["Cookie"] == nil)
        #expect(request.method == "POST")
        #expect(request.url.path == "/v1/signals/events")
        #expect(request.headers["X-App-ID"] == "dream-eater")
        #expect(request.headers["X-Platform"] == "ios")
        #expect(request.headers["X-App-Version"] == "2.1")
        #expect(request.headers["Content-Type"] == "application/json")
    }

    @Test func aBodyHoldsOnlyEventNamesAndTheCallersProps() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals(tokenProvider: { "secret-midgar-token" })
        await signals.record("paywall.view", props: ["placement": "settings"])
        await signals.record("app.launch")

        await signals.flush()

        let request = try #require(harness.host.requests.first)
        let body = try #require(request.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["events"])
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.allSatisfy { Set($0.keys).isSubset(of: ["name", "props"]) })
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("secret-midgar-token"))
        #expect(!text.contains("dream-eater"))
        #expect(!text.contains("@"))
    }

    @Test func platformAndVersionHeadersFollowTheInjectedValues() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])

        let ipad = harness.makeSignals(platform: "ipados", appVersion: "3.4.5")
        await ipad.record("app.launch")
        await ipad.flush()
        let bare = harness.makeSignals(platform: "linux", appVersion: nil)
        await bare.record("app.launch")
        await bare.flush()

        let requests = harness.host.requests
        #expect(requests.first?.headers["X-Platform"] == "ipados")
        #expect(requests.first?.headers["X-App-Version"] == "3.4.5")
        #expect(requests.last?.headers["X-Platform"] == "linux")
        #expect(requests.last?.headers["X-App-Version"] == nil)
    }

    @Test func theHostPlatformIsTheOneTheCodeWasBuiltFor() {
        #if os(macOS)
        #expect(MidgarSignalsPlatform.current == "macos")
        #elseif os(Linux)
        #expect(MidgarSignalsPlatform.current == "linux")
        #endif
        let accepted = ["ios", "ipados", "macos", "tvos", "visionos", "watchos", "linux", "android"]
        #expect(accepted.contains(MidgarSignalsPlatform.current))
    }

    @Test func propsKeepTheirTypesAndStringsAreCappedAt64Characters() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()
        await signals.record("tap", props: [
            "text": .string(String(repeating: "a", count: 100)),
            "count": .int(3),
            "ratio": .double(0.5),
            "flag": .bool(true),
            "bad": .double(.infinity)
        ])

        await signals.flush()

        let props = try #require(harness.sentBatches.first?.first?["props"] as? [String: Any])
        #expect((props["text"] as? String)?.count == 64)
        #expect(props["count"] as? Int == 3)
        #expect(props["ratio"] as? Double == 0.5)
        #expect(props["flag"] as? Bool == true)
        #expect(props["bad"] == nil)
        let body = String(decoding: try #require(harness.host.requests.first?.body), as: UTF8.self)
        #expect(body.contains(#""flag":true"#))
        #expect(body.contains(#""count":3"#))
    }

    @Test func cappingNeverSplitsACharacterAndCountsUTF16Units() {
        let capped = MidgarSignalValue.capped(String(repeating: "\u{1F600}", count: 40))
        #expect(capped.utf16.count == 64)
        #expect(capped.count == 32)
        #expect(MidgarSignalValue.capped("short") == "short")
        #expect(MidgarSignalValue.capped(String(repeating: "b", count: 64)).count == 64)
    }

    @Test func anEmptyNameIsNotQueued() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.record("")

        #expect(await signals.pendingCount == 0)
    }

    @Test func configureMakesTheSharedInstanceAndSharedIsNilBeforeThat() {
        MidgarSignalsRegistry.install(nil)
        #expect(MidgarSignals.shared == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signals-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let signals = MidgarSignals.configure(
            configuration: MidgarHTTPConfiguration(appID: "dream-eater"),
            directory: directory
        )

        #expect(MidgarSignals.shared === signals)
        #expect(MidgarSignals.isEnabled)
        MidgarSignals.isEnabled = false
        #expect(!signals.isEnabled)
        #expect(!MidgarSignals.isEnabled)
        MidgarSignalsRegistry.install(nil)
        #expect(MidgarSignals.isEnabled)
    }
}
