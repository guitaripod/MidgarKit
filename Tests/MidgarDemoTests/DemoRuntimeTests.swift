import Foundation
import Testing
import MidgarDemo

/// Records what `prepare` received. An actor, so the recorder can be shared with a `Sendable` world.
actor PrepareLog {
    private(set) var scenes: [String] = []
    private(set) var dates: [Date] = []

    func record(_ scene: DemoScene, context: DemoContext) {
        scenes.append(scene.id)
        dates.append(context.date)
    }
}

struct FixtureWorld: DemoWorld {
    let id: String
    let scenes: [DemoScene]
    let log: PrepareLog

    func prepare(_ scene: DemoScene, context: DemoContext) async throws {
        await log.record(scene, context: context)
    }
}

/// Every test here activates a registry, which writes the process-wide frozen clock, so the suite runs serially.
@Suite(.serialized) struct MidgarDemoRuntimeTests {
    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private static let frozenDate = Date(timeIntervalSince1970: 1_792_143_660)

    private static func makeRegistry(log: PrepareLog) throws -> DemoRegistry {
        var registry = DemoRegistry()
        try registry.register(FixtureWorld(id: "daily", scenes: [DemoScene(id: "play"), DemoScene(id: "result")], log: log))
        try registry.register(FixtureWorld(id: "solo", scenes: [DemoScene(id: "album")], log: log))
        return registry
    }

    private static func launch(world: String? = "daily", scene: String? = nil, date: Date? = nil, locale: String? = nil) -> DemoLaunch {
        DemoLaunch(world: world, scene: scene, date: date, locale: locale)
    }

    @Test func activatesKnownWorldAndScene() async throws {
        let log = PrepareLog()
        let registry = try Self.makeRegistry(log: log)
        let activation = try await registry.activate(launch: Self.launch(scene: "result", date: Self.frozenDate), now: Self.fixedNow)
        #expect(activation?.world.id == "daily")
        #expect(activation?.scene == DemoScene(id: "result"))
        #expect(await log.scenes == ["result"])
    }

    @Test func missingSceneUsesTheFirstScene() async throws {
        let log = PrepareLog()
        let registry = try Self.makeRegistry(log: log)
        let activation = try await registry.activate(launch: Self.launch(), now: Self.fixedNow)
        #expect(activation?.scene == DemoScene(id: "play"))
        #expect(await log.scenes == ["play"])
    }

    @Test func unknownWorldNamesTheValidWorlds() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        await #expect(throws: DemoError.unknownWorld("nope", valid: ["daily", "solo"])) {
            try await registry.activate(launch: Self.launch(world: "nope"), now: Self.fixedNow)
        }
    }

    @Test func unknownSceneNamesTheValidScenes() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        await #expect(throws: DemoError.unknownScene(world: "daily", scene: "x", valid: ["play", "result"])) {
            try await registry.activate(launch: Self.launch(scene: "x"), now: Self.fixedNow)
        }
    }

    @Test func worldWithoutScenesRejectsMissingScene() async throws {
        var registry = DemoRegistry()
        try registry.register(FixtureWorld(id: "empty", scenes: [], log: PrepareLog()))
        await #expect(throws: DemoError.noScenes(world: "empty")) {
            try await registry.activate(launch: Self.launch(world: "empty"), now: Self.fixedNow)
        }
    }

    @Test func worldWithoutScenesRejectsNamedScene() async throws {
        var registry = DemoRegistry()
        try registry.register(FixtureWorld(id: "empty", scenes: [], log: PrepareLog()))
        await #expect(throws: DemoError.unknownScene(world: "empty", scene: "play", valid: [])) {
            try await registry.activate(launch: Self.launch(world: "empty", scene: "play"), now: Self.fixedNow)
        }
    }

    @Test func outsideDemoModeActivatesNothing() async throws {
        let log = PrepareLog()
        let registry = try Self.makeRegistry(log: log)
        let activation = try await registry.activate(launch: Self.launch(world: nil, scene: "result"), now: Self.fixedNow)
        #expect(activation == nil)
        #expect(await log.scenes.isEmpty)
    }

    @Test func registeringTwoWorldsWithOneIdFails() throws {
        var registry = DemoRegistry()
        try registry.register(FixtureWorld(id: "daily", scenes: [], log: PrepareLog()))
        #expect(throws: DemoError.duplicateWorld("daily")) {
            try registry.register(FixtureWorld(id: "daily", scenes: [DemoScene(id: "play")], log: PrepareLog()))
        }
        #expect(registry.worlds.count == 1)
    }

    @Test func contextCarriesDemoModeFlagsByDefault() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        let activation = try await registry.activate(launch: Self.launch(), now: Self.fixedNow)
        let context = try #require(activation?.context)
        #expect(context.skipOnboarding)
        #expect(context.hidePaywall)
        #expect(context.suppressReviewPrompts)
        #expect(context.suppressNetwork)
    }

    @Test func contextFlagsCanBeOverridden() {
        let context = DemoContext(
            date: Self.fixedNow,
            locale: Locale(identifier: "en_US"),
            skipOnboarding: false,
            hidePaywall: false,
            suppressReviewPrompts: false,
            suppressNetwork: false
        )
        #expect(!context.skipOnboarding)
        #expect(!context.hidePaywall)
        #expect(!context.suppressReviewPrompts)
        #expect(!context.suppressNetwork)
    }

    @Test func contextUsesLaunchLocaleOrTheCurrentOne() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        let named = try await registry.activate(launch: Self.launch(locale: "fi_FI"), now: Self.fixedNow)
        #expect(named?.context.locale == Locale(identifier: "fi_FI"))
        let unnamed = try await registry.activate(launch: Self.launch(), now: Self.fixedNow)
        #expect(unnamed?.context.locale == Locale.current)
    }

    @Test func contextDateDefaultsToTheActivationTime() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        let activation = try await registry.activate(launch: Self.launch(), now: Self.fixedNow)
        #expect(activation?.context.date == Self.fixedNow)
    }

    @Test func clockIsFrozenInDemoMode() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        _ = try await registry.activate(launch: Self.launch(date: Self.frozenDate), now: Self.fixedNow)
        #expect(DemoClock.now == Self.frozenDate)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(DemoClock.now == Self.frozenDate)
    }

    @Test func clockIsFrozenAtActivationWhenNoDateIsGiven() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        _ = try await registry.activate(launch: Self.launch(), now: Self.fixedNow)
        #expect(DemoClock.now == Self.fixedNow)
    }

    @Test func prepareSeesTheFrozenClock() async throws {
        let log = PrepareLog()
        let registry = try Self.makeRegistry(log: log)
        _ = try await registry.activate(launch: Self.launch(date: Self.frozenDate), now: Self.fixedNow)
        #expect(await log.dates == [Self.frozenDate])
    }

    @Test func clockIsLiveOutsideDemoMode() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        _ = try await registry.activate(launch: Self.launch(date: Self.frozenDate), now: Self.fixedNow)
        _ = try await registry.activate(launch: Self.launch(world: nil), now: Self.fixedNow)
        let drift = abs(DemoClock.now.timeIntervalSinceNow)
        #expect(drift < 5)
    }

    @Test func failedActivationClearsTheFrozenClock() async throws {
        let registry = try Self.makeRegistry(log: PrepareLog())
        _ = try await registry.activate(launch: Self.launch(date: Self.frozenDate), now: Self.fixedNow)
        await #expect(throws: DemoError.self) {
            try await registry.activate(launch: Self.launch(world: "nope", date: Self.frozenDate), now: Self.fixedNow)
        }
        let drift = abs(DemoClock.now.timeIntervalSinceNow)
        #expect(drift < 5)
    }

    @Test func unknownSceneErrorMessageNamesTheIds() {
        let error = DemoError.unknownScene(world: "daily", scene: "x", valid: ["play", "result"])
        #expect(error.errorDescription == "Unknown scene \"x\" in demo world \"daily\". Valid scenes: play, result.")
    }

    @Test func unknownWorldErrorMessageSaysWhenThereAreNoWorlds() {
        let error = DemoError.unknownWorld("daily", valid: [])
        #expect(error.errorDescription == "Unknown demo world \"daily\". Valid worlds: none.")
    }

    @Test func theClockStaysLiveWhenPrepareThrows() async throws {
        var registry = DemoRegistry()
        try registry.register(ThrowingWorld())
        await #expect(throws: PrepareFailure.self) {
            try await registry.activate(launch: Self.launch(world: "daily", date: Self.frozenDate), now: Self.fixedNow)
        }
        #expect(abs(DemoClock.now.timeIntervalSinceNow) < 5)
    }

    @Test func theClockFreezesOnlyAfterPrepareReturns() async throws {
        let observed = ClockObservation()
        var registry = DemoRegistry()
        try registry.register(ObservingWorld(observed: observed))
        _ = try await registry.activate(launch: Self.launch(world: "observing", date: Self.frozenDate), now: Self.fixedNow)
        #expect(abs(await observed.clockDuringPrepare.timeIntervalSinceNow) < 5)
        #expect(DemoClock.now == Self.frozenDate)
    }

    @Test func aPreviousFrozenClockIsClearedWhenPrepareThrows() async throws {
        var registry = DemoRegistry()
        try registry.register(ThrowingWorld())
        try registry.register(FixtureWorld(id: "ok", scenes: [DemoScene(id: "s")], log: PrepareLog()))
        _ = try await registry.activate(launch: Self.launch(world: "ok", date: Self.frozenDate), now: Self.fixedNow)
        #expect(DemoClock.now == Self.frozenDate)

        await #expect(throws: PrepareFailure.self) {
            try await registry.activate(launch: Self.launch(world: "daily", date: Self.frozenDate), now: Self.fixedNow)
        }

        #expect(abs(DemoClock.now.timeIntervalSinceNow) < 5)
    }

    @Test func aBuildThatIsNotPermittedIgnoresTheContract() async throws {
        let log = PrepareLog()
        let registry = try Self.makeRegistry(log: log)
        let activation = try await registry.activate(launch: Self.launch(date: Self.frozenDate), now: Self.fixedNow, isPermitted: false)
        #expect(activation == nil)
        #expect(await log.scenes.isEmpty)
        #expect(abs(DemoClock.now.timeIntervalSinceNow) < 5)
    }

    @Test func releaseBuildsNeedTheInfoPlistFlag() {
        #expect(DemoGate.isPermitted(isDebugBuild: true, infoDictionary: nil))
        #expect(!DemoGate.isPermitted(isDebugBuild: false, infoDictionary: nil))
        #expect(!DemoGate.isPermitted(isDebugBuild: false, infoDictionary: ["MidgarDemoEnabled": false]))
        #expect(!DemoGate.isPermitted(isDebugBuild: false, infoDictionary: ["MidgarDemoEnabled": "NO"]))
        #expect(DemoGate.isPermitted(isDebugBuild: false, infoDictionary: ["MidgarDemoEnabled": true]))
        #expect(DemoGate.isPermitted(isDebugBuild: false, infoDictionary: ["MidgarDemoEnabled": "YES"]))
    }
}

struct PrepareFailure: Error {}

struct ThrowingWorld: DemoWorld {
    let id = "daily"
    let scenes = [DemoScene(id: "play")]

    func prepare(_ scene: DemoScene, context: DemoContext) async throws {
        throw PrepareFailure()
    }
}

actor ClockObservation {
    private(set) var clockDuringPrepare = Date.distantPast

    func record(_ date: Date) {
        clockDuringPrepare = date
    }
}

struct ObservingWorld: DemoWorld {
    let id = "observing"
    let scenes = [DemoScene(id: "play")]
    let observed: ClockObservation

    func prepare(_ scene: DemoScene, context: DemoContext) async throws {
        await observed.record(DemoClock.now)
    }
}
