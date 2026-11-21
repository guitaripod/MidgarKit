import Foundation
import Testing
@testable import MidgarCore

private let appUUID = "5F8A2C1E-0B7D-4E11-9A3C-2D6F4B8E7A10"
private let systemUUID = "0C4D9E22-7A61-4B5F-8E0D-91B3C5A7F2E4"
private let binaries: Set<String> = ["Flaccy", "FlaccyKit"]

private func frame(_ binary: String, _ uuid: String, _ offset: Int, samples: Int = 1, sub: [String] = []) -> String {
    #"{"binaryUUID":"\#(uuid)","offsetIntoBinaryTextSegment":\#(offset),"sampleCount":\#(samples),"binaryName":"\#(binary)","address":4096,"subFrames":[\#(sub.joined(separator: ","))]}"#
}

private func crash(
    meta: String = #""exceptionType":1,"signal":11,"terminationReason":"Namespace SIGNAL, Code 11 Segmentation fault: 11","appBuildVersion":"412","osVersion":"iPhone OS 27.1 (25B80)","deviceType":"iPhone17,3","bundleIdentifier":"com.midgarcorp.flaccy","virtualMemoryRegionInfo":"0 is not in any region. Bytes before following region: 4000""#,
    root: String? = nil
) -> String {
    let chain = root ?? frame("libswiftCore.dylib", systemUUID, 9_912, sub: [frame("Flaccy", appUUID.lowercased(), 482_112, sub: [frame("FlaccyKit", appUUID, 77_120, sub: [frame("UIKitCore", systemUUID, 5)])])])
    return #"{"callStackTree":{"callStackPerThread":true,"callStacks":[{"threadAttributed":false,"callStackRootFrames":[\#(frame("libsystem_kernel.dylib", systemUUID, 1))]},{"threadAttributed":true,"callStackRootFrames":[\#(chain)]}]},"diagnosticMetaData":{\#(meta)}}"#
}

private func payload(crashes: [String] = [], hangs: [String] = [], extra: String = "") -> Data {
    Data(#"{"timeStampBegin":"2026-11-20 00:00:00 +0000","timeStampEnd":"2026-11-21 00:00:00 +0000","crashDiagnostics":[\#(crashes.joined(separator: ","))],"hangDiagnostics":[\#(hangs.joined(separator: ","))]\#(extra)}"#.utf8)
}

private func cards(_ data: Data, trail: MidgarTrailSnapshot? = nil) -> [MidgarCrashCard] {
    MidgarCrashCards.cards(fromDiagnosticJSON: data, appBinaries: binaries, trail: trail)
}

private func day(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
}

@Suite struct CrashCardTests {
    @Test func aCrashBecomesACardOfNamesAddressesAndWhereItRan() throws {
        let card = try #require(cards(payload(crashes: [crash()])).first)
        #expect(card.kind == .crash)
        #expect(card.type == "EXC_BAD_ACCESS")
        #expect(card.signal == "SIGSEGV")
        #expect(card.code == "Namespace SIGNAL, Code 11 Segmentation fault: 11")
        #expect(card.build == "412")
        #expect(card.os == "27.1")
        #expect(card.device == "iPhone17,3")
        #expect(card.trail == nil)
        #expect(card.frames == [
            MidgarCrashFrame(binary: "libswiftCore.dylib", uuid: systemUUID, offset: 9_912, inApp: false),
            MidgarCrashFrame(binary: "Flaccy", uuid: appUUID, offset: 482_112, inApp: true),
            MidgarCrashFrame(binary: "FlaccyKit", uuid: appUUID, offset: 77_120, inApp: true),
            MidgarCrashFrame(binary: "UIKitCore", uuid: systemUUID, offset: 5, inApp: false)
        ])
    }

    @Test func itIsSentInTheShapeTheServerChecks() throws {
        let card = try #require(cards(payload(crashes: [crash()])).first)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as? [String: Any])
        #expect(Set(object.keys) == ["kind", "type", "signal", "code", "frames", "build", "os", "device"])
        let frames = try #require(object["frames"] as? [[Any]])
        #expect(frames[1][0] as? String == "Flaccy")
        #expect(frames[1][1] as? String == appUUID)
        #expect(frames[1][2] as? Int == 482_112)
        #expect(frames[1][3] as? Int == 1)
        #expect(frames[0][3] as? Int == 0)
        #expect(try JSONDecoder().decode(MidgarCrashCard.self, from: JSONEncoder().encode(card)) == card)
    }

    @Test func nothingOfTheMemoryMapTheBundleOrTheExceptionMessageIsKept() throws {
        let meta = #""exceptionType":"10","signal":"6","objectiveCexceptionReason":{"composedMessage":"index 5 beyond bounds for marcus@example.com","formatString":"index %lu beyond bounds for %@","arguments":["5","marcus@example.com"],"exceptionType":"NSException","className":"NSArray","exceptionName":"NSRangeException"},"virtualMemoryRegionInfo":"secret","bundleIdentifier":"com.midgarcorp.flaccy","regionFormat":"FI""#
        let card = try #require(cards(payload(crashes: [crash(meta: meta)])).first)
        #expect(card.type == "EXC_CRASH")
        #expect(card.signal == "SIGABRT")
        #expect(card.objcName == "NSRangeException")
        #expect(card.objcClass == "NSArray")
        let text = String(decoding: try JSONEncoder().encode(card), as: UTF8.self)
        for leak in ["marcus", "beyond bounds", "secret", "com.midgarcorp", "FI\""] {
            #expect(!text.contains(leak))
        }
    }

    @Test func textThatIsNotWhatItShouldBeIsLeftOut() throws {
        let meta = #""exceptionType":99,"signal":77,"terminationReason":"<RBSTerminateContext| domain:10 code:0x8BADF00D /Users/marcus/x ä>","appBuildVersion":"1.2.3","osVersion":"unknown","deviceType":"my phone","objectiveCexceptionReason":{"exceptionName":"bad name!","className":"9Class"}"#
        let card = try #require(cards(payload(crashes: [crash(meta: meta)])).first)
        #expect(card.type == "EXC_99")
        #expect(card.signal == "SIG77")
        #expect(card.code == "<RBSTerminateContext domain:10 code:0x8BADF00D Usersmarcusx >")
        #expect(card.build == nil)
        #expect(card.os == nil)
        #expect(card.device == nil)
        #expect(card.objcName == nil)
        #expect(card.objcClass == nil)
    }

    @Test func atMostSixteenFramesNearestTheFaultAreKept() throws {
        let deep = (0..<40).reversed().reduce("") { inner, index in frame("Flaccy", appUUID, index, sub: inner.isEmpty ? [] : [inner]) }
        let card = try #require(cards(payload(crashes: [crash(root: deep)])).first)
        #expect(card.frames.count == 16)
        #expect(card.frames.map(\.offset) == Array(0..<16))
    }

    @Test func aFrameWithoutAUUIDOrOffsetIsSkippedAndACardWithNoFrameIsNotMade() {
        let broken = frame("Flaccy", "not-a-uuid", 1, sub: [frame("Flaccy", appUUID, -4)])
        #expect(cards(payload(crashes: [crash(root: broken)])).isEmpty)
        let mixed = frame("Flaccy", "not-a-uuid", 1, sub: [frame("Flaccy/../x~", appUUID, 8)])
        #expect(cards(payload(crashes: [crash(root: mixed)])).map(\.frames) == [[MidgarCrashFrame(binary: "Flaccy..x", uuid: appUUID, offset: 8, inApp: false)]])
    }

    @Test func aSampledTreeIsReadAlongItsHeaviestPathFromTheLeaf() throws {
        let tree = frame("Flaccy", appUUID, 1, samples: 20, sub: [
            frame("Flaccy", appUUID, 2, samples: 3, sub: [frame("Flaccy", appUUID, 4, samples: 3)]),
            frame("Flaccy", appUUID, 3, samples: 17, sub: [frame("libsystem_kernel.dylib", systemUUID, 5, samples: 17)])
        ])
        let hang = #"{"callStackTree":{"callStackPerThread":false,"callStacks":[{"callStackRootFrames":[\#(tree)]}]},"diagnosticMetaData":{"hangDuration":"20 sec","osVersion":"macOS 27.3 (26D5)","deviceType":"Mac16,1"}}"#
        let card = try #require(cards(payload(hangs: [hang])).first)
        #expect(card.kind == .hang)
        #expect(card.type == nil)
        #expect(card.os == "27.3")
        #expect(card.frames.map(\.offset) == [5, 3, 1])
    }

    @Test func everyKindOfDiagnosticGivesItsOwnCardCrashesFirst() {
        let other = #"{"callStackTree":{"callStackPerThread":true,"callStacks":[{"threadAttributed":true,"callStackRootFrames":[\#(frame("Flaccy", appUUID, 9))]}]},"diagnosticMetaData":{}}"#
        let data = payload(crashes: [crash()], hangs: [other], extra: #","cpuExceptionDiagnostics":[\#(other)],"diskWriteExceptionDiagnostics":[\#(other)],"appLaunchDiagnostics":[\#(other)]"#)
        #expect(cards(data).map(\.kind) == [.crash, .launch, .hang, .cpu, .disk])
    }

    @Test func aPayloadThatIsNotOneGivesNothing() {
        #expect(cards(Data("not json".utf8)).isEmpty)
        #expect(cards(Data("{}".utf8)).isEmpty)
        #expect(cards(Data(#"{"crashDiagnostics":[{"diagnosticMetaData":{}}]}"#.utf8)).isEmpty)
    }

    @Test func theKeyRestsOnTheAppsOwnFramesAndNotOnWhereItRan() throws {
        let one = try #require(cards(payload(crashes: [crash()])).first)
        let elsewhere = try #require(cards(payload(crashes: [crash(meta: #""exceptionType":1,"osVersion":"iPhone OS 26.0","deviceType":"iPad14,1""#)])).first)
        let other = try #require(cards(payload(crashes: [crash(root: frame("Flaccy", appUUID, 1))])).first)
        #expect(one.key == elsewhere.key)
        #expect(one.key != other.key)
        #expect(one.key == "crash|EXC_BAD_ACCESS||\(appUUID):482112|\(appUUID):77120")
    }
}

@Suite struct CrashTrailTests {
    private let snapshot = MidgarTrailSnapshot(screens: ["library", "album", "Player!", "player"], at: day("2026-11-20T18:30:00Z"))

    @Test func aCrashCarriesTheTrailOfTheRunItEnded() throws {
        let card = try #require(cards(payload(crashes: [crash()]), trail: snapshot).first)
        #expect(card.trail == ["library", "album", "player"])
    }

    @Test func aTrailFromOutsideThePayloadsWindowIsNotPutOnIt() throws {
        var stale = snapshot
        stale.at = day("2026-11-18T10:00:00Z")
        #expect(try #require(cards(payload(crashes: [crash()]), trail: stale).first).trail == nil)
        var edge = snapshot
        edge.at = day("2026-11-21T00:30:00Z")
        #expect(try #require(cards(payload(crashes: [crash()]), trail: edge).first).trail != nil)
    }

    @Test func onlyACrashCarriesATrailAndOnlyTheLastTwentyScreens() throws {
        let other = #"{"callStackTree":{"callStackPerThread":true,"callStacks":[{"threadAttributed":true,"callStackRootFrames":[\#(frame("Flaccy", appUUID, 9))]}]},"diagnosticMetaData":{}}"#
        let long = MidgarTrailSnapshot(screens: (0..<30).map { "screen_\($0)" }, at: snapshot.at)
        let made = cards(payload(crashes: [crash()], hangs: [other]), trail: long)
        #expect(made.first?.trail == (10..<30).map { "screen_\($0)" })
        #expect(made.last?.trail == nil)
    }

    @Test func theStoreKeepsTheLastTwentyAndLeavesThemForTheNextRun() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("trail-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = MidgarTrailStore(fileURL: file)
        #expect(first.previous == nil)
        for index in 0..<25 {
            first.mark("screen_\(index)", at: day("2026-11-20T18:30:00Z"))
        }
        first.waitForWrites()
        #expect(first.current == (5..<25).map { "screen_\($0)" })

        let next = MidgarTrailStore(fileURL: file)
        #expect(next.previous == MidgarTrailSnapshot(screens: (5..<25).map { "screen_\($0)" }, at: day("2026-11-20T18:30:00Z")))
        #expect(next.current.isEmpty)
        next.clear()
        next.waitForWrites()
        #expect(MidgarTrailStore(fileURL: file).previous == nil)
    }

    @Test func aScreenIsAShortLowercaseId() {
        for good in ["player", "album_detail", "s2", "a", String(repeating: "a", count: 40)] {
            #expect(MidgarTrail.isScreenID(good))
        }
        for bad in ["", "Player", "my screen", "2fast", "_private", "pl\u{E4}yer", "now-playing", String(repeating: "a", count: 41), "marcus@example.com"] {
            #expect(!MidgarTrail.isScreenID(bad))
        }
    }
}

@Suite struct CrashCardSendingTests {
    private func diagnostics(_ harness: SignalsHarness) -> [CapturedRequest] {
        harness.host.requests.filter { $0.url.path.hasSuffix("/signals/diagnostics") }
    }

    private func sentCards(_ request: CapturedRequest) -> [[String: Any]] {
        guard let body = request.body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return []
        }
        return object["cards"] as? [[String: Any]] ?? []
    }

    private var stateFile: (SignalsHarness) -> URL {
        { MidgarSignalsStore(directory: $0.directory, appID: $0.appID).sibling("diagnostics") }
    }

    @Test func aPayloadIsSentAsCardsWithThePlatformAndVersionAndNoIdentity() async throws {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply])
        let signals = harness.makeSignals()

        await signals.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)

        let request = try #require(diagnostics(harness).first)
        #expect(request.method == "POST")
        #expect(request.headers["X-Platform"] == "ios")
        #expect(request.headers["X-App-Version"] == "2.1")
        #expect(request.headers["X-App-ID"] == "dream-eater")
        #expect(request.headers["Authorization"] == nil)
        #expect(sentCards(request).count == 1)
        #expect(sentCards(request).first?["type"] as? String == "EXC_BAD_ACCESS")
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(harness)).load().pending.isEmpty)
    }

    @Test func theSameFaultIsTakenOnceADayAndAgainTheNextDay() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])
        let signals = harness.makeSignals()

        await signals.recordDiagnosticJSON(payload(crashes: [crash(), crash()]), appBinaries: binaries, trail: nil)
        await signals.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(diagnostics(harness).count == 1)
        #expect(sentCards(diagnostics(harness)[0]).count == 1)

        harness.clock.advance(by: 86_400)
        await signals.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(diagnostics(harness).count == 2)
    }

    @Test func atMostFiveFaultsAreTakenInADay() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([acceptedReply, acceptedReply])
        let signals = harness.makeSignals()
        let many = (1...8).map { crash(root: frame("Flaccy", appUUID, $0)) }

        await signals.recordDiagnosticJSON(payload(crashes: many), appBinaries: binaries, trail: nil)

        #expect(diagnostics(harness).count == 1)
        #expect(sentCards(diagnostics(harness)[0]).count == 5)
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(harness)).load().pending.isEmpty)
    }

    @Test func cardsThatCannotBeSentWaitOnDiskForTheNextLaunch() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.json(503, "{}")])
        let signals = harness.makeSignals()

        await signals.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(harness)).load().pending.count == 1)

        harness.host.enqueue([acceptedReply])
        let relaunched = harness.makeSignals()
        await relaunched.sendPendingCards()
        #expect(diagnostics(harness).count == 2)
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(harness)).load().pending.isEmpty)
    }

    @Test func cardsTheServerRefusesForGoodAreForgotten() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        harness.host.enqueue([.json(400, #"{"error":{"code":"invalid_request","message":"no"}}"#)])
        let signals = harness.makeSignals()

        await signals.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)

        #expect(diagnostics(harness).count == 1)
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(harness)).load().pending.isEmpty)
    }

    @Test func nothingIsKeptOrSentWhileUsageCountsAreOffKilledOrFromATestInstall() async throws {
        let off = SignalsHarness()
        defer { off.cleanUp() }
        let silenced = off.makeSignals()
        silenced.setEnabled(false)
        await silenced.recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(off.host.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stateFile(off).path))

        let killed = SignalsHarness()
        defer { killed.cleanUp() }
        killed.config.value = try killedSignalsConfig()
        await killed.makeSignals().recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(killed.host.requests.isEmpty)

        let test = SignalsHarness()
        defer { test.cleanUp() }
        await test.makeSignals(isTestInstall: { true }).recordDiagnosticJSON(payload(crashes: [crash()]), appBinaries: binaries, trail: nil)
        #expect(test.host.requests.isEmpty)
        #expect(MidgarDiagnosticsStore(fileURL: stateFile(test)).load().pending.isEmpty)
    }

    @Test func aPayloadWithNoUsableDiagnosticSendsNothing() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        await harness.makeSignals().recordDiagnosticJSON(Data("{}".utf8), appBinaries: binaries, trail: nil)
        #expect(harness.host.requests.isEmpty)
    }

    @Test func theHashOfAKeyIsTheSameInEveryLaunch() {
        #expect(MidgarSignals.stableHash("crash|EXC_BAD_ACCESS") == MidgarSignals.stableHash("crash|EXC_BAD_ACCESS"))
        #expect(MidgarSignals.stableHash("") == "cbf29ce484222325")
        #expect(MidgarSignals.stableHash("a") == "af63dc4c8601ec8c")
        #expect(MidgarSignals.dayKey(Date(timeIntervalSince1970: 1_795_219_200)) == "2026-11-21")
    }
}

@Suite struct HealthSignalTests {
    private struct Metrics: MidgarMetricPayload {
        var coldLaunchMedianMilliseconds: Double?
        var hangSecondsPerHour: Double?
        var cumulativeForegroundSeconds: Double?
        var peakMemoryMegabytes: Double?
        var exits: MidgarExitCounts?
    }

    private struct Diagnostics: MidgarDiagnosticPayload {
        var crashCount = 0
        var hangCount = 0
        var diskWriteCount = 0
        var cpuExceptionCount = 0
    }

    @Test func exitCountsBecomeOneEventAndADayWithAMemoryOrWatchdogEndIsMarked() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.recordDailyMetrics(Metrics(exits: MidgarExitCounts(foregroundMemory: 2, foregroundWatchdog: 1, foregroundAbnormal: 0, backgroundMemory: 7)))
        let sent = await harness.drain(signals)

        #expect(sent.map(\.name) == ["metrics.daily", "metrics.exits", "health.crashed", "health.crashed"])
        #expect(sent[1].props as? [String: Int] == ["foregroundMemory": 2, "foregroundWatchdog": 1, "foregroundAbnormal": 0, "backgroundMemory": 7])
        #expect(sent.suffix(2).compactMap { $0.props["kind"] as? String } == ["memory", "watchdog"])
    }

    @Test func aPayloadWithoutExitCountsSendsOnlyTheDailyEvent() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()
        await signals.recordDailyMetrics(Metrics(coldLaunchMedianMilliseconds: 400))
        #expect(await harness.drain(signals).map(\.name) == ["metrics.daily"])
    }

    @Test func aDayWithACrashOrAFreezeIsMarkedOncePerKind() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.recordDiagnostics(Diagnostics(crashCount: 3, hangCount: 1))
        await signals.recordDiagnostics(Diagnostics(crashCount: 1))
        let sent = await harness.drain(signals)

        #expect(sent.filter { $0.name == "health.crashed" }.compactMap { $0.props["kind"] as? String } == ["crash", "hang"])
        #expect(sent.filter { $0.name == "metrics.diagnostics" }.count == 2)
    }

    @Test func aFailureIsCountedOnceADayByWhatFailedAndWhy() async {
        let harness = SignalsHarness()
        defer { harness.cleanUp() }
        let signals = harness.makeSignals()

        await signals.send(.errorHit(domain: .purchase, code: .offline))
        await signals.send(.errorHit(domain: .purchase, code: .offline))
        await signals.send(.errorHit(domain: .import, code: .corrupt))
        let sent = await harness.drain(signals)

        #expect(sent.map(\.name) == ["error.hit", "error.hit"])
        #expect(sent.compactMap { $0.props["code"] as? String } == ["offline", "corrupt"])
    }
}
