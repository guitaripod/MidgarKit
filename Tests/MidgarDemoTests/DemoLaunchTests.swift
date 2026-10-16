import Foundation
import Testing
import MidgarDemo

@Suite struct MidgarDemoLaunchTests {
    private static let fullArguments = [
        "-MidgarDemo", "daily",
        "-MidgarDemoScene", "result",
        "-MidgarDemoDate", "2026-10-16T09:41:00Z",
        "-MidgarDemoLocale", "fi_FI",
    ]

    /// 2026-10-16T09:41:00Z, as seconds since 1970.
    private static let october16 = Date(timeIntervalSince1970: 1_792_143_660)

    @Test func parsesEveryArgument() throws {
        let launch = try DemoLaunch.parse(arguments: Self.fullArguments, environment: [:])
        #expect(launch.world == "daily")
        #expect(launch.scene == "result")
        #expect(launch.date == Self.october16)
        #expect(launch.locale == "fi_FI")
        #expect(launch.isEnabled)
    }

    @Test func readsEnvironmentWhenArgumentsAreAbsent() throws {
        let environment = [
            "MIDGAR_DEMO": "daily",
            "MIDGAR_DEMO_SCENE": "result",
            "MIDGAR_DEMO_DATE": "2026-10-16T09:41:00Z",
            "MIDGAR_DEMO_LOCALE": "fi_FI",
        ]
        let launch = try DemoLaunch.parse(arguments: [], environment: environment)
        #expect(launch == DemoLaunch(world: "daily", scene: "result", date: Self.october16, locale: "fi_FI"))
    }

    @Test func argumentsWinOverEnvironment() throws {
        let launch = try DemoLaunch.parse(
            arguments: ["-MidgarDemo", "solo", "-MidgarDemoDate", "2026-01-01T00:00:00Z"],
            environment: ["MIDGAR_DEMO": "daily", "MIDGAR_DEMO_DATE": "2026-10-16T09:41:00Z", "MIDGAR_DEMO_SCENE": "result"]
        )
        #expect(launch.world == "solo")
        #expect(launch.date == Date(timeIntervalSince1970: 1_767_225_600))
        #expect(launch.scene == "result")
    }

    @Test func emptyEnvironmentValueCountsAsUnset() throws {
        let launch = try DemoLaunch.parse(arguments: [], environment: ["MIDGAR_DEMO": ""])
        #expect(launch.world == nil)
        #expect(!launch.isEnabled)
    }

    @Test func noKeysMeansNoDemo() throws {
        let launch = try DemoLaunch.parse(arguments: ["-AppleLocale", "fi_FI"], environment: [:])
        #expect(launch == DemoLaunch(world: nil, scene: nil, date: nil, locale: nil))
        #expect(!launch.isEnabled)
    }

    @Test func sceneWithoutWorldIsIgnoredOutsideDemoMode() throws {
        let launch = try DemoLaunch.parse(arguments: ["-MidgarDemoScene", "result"], environment: [:])
        #expect(!launch.isEnabled)
        #expect(launch.scene == "result")
    }

    @Test func fractionalSecondsAreAccepted() throws {
        let launch = try DemoLaunch.parse(arguments: ["-MidgarDemoDate", "2026-10-16T09:41:00.500Z"], environment: [:])
        #expect(launch.date == Date(timeIntervalSince1970: 1_792_143_660.5))
    }

    @Test func malformedDateThrowsNamingTheValue() {
        #expect(throws: DemoError.malformedDate("yesterday")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemoDate", "yesterday"], environment: [:])
        }
    }

    @Test func dateWithoutTimeZoneIsRejected() {
        #expect(throws: DemoError.malformedDate("2026-10-16")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemoDate", "2026-10-16"], environment: [:])
        }
    }

    @Test func malformedEnvironmentDateThrows() {
        #expect(throws: DemoError.malformedDate("16.10.2026")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemo", "daily"], environment: ["MIDGAR_DEMO_DATE": "16.10.2026"])
        }
    }

    @Test func argumentWithoutValueThrows() {
        #expect(throws: DemoError.missingValue(argument: "-MidgarDemo")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemo"], environment: [:])
        }
    }

    @Test func argumentFollowedByAnotherKeyThrows() {
        #expect(throws: DemoError.missingValue(argument: "-MidgarDemo")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemo", "-MidgarDemoScene", "result"], environment: [:])
        }
    }

    @Test func trailingSceneArgumentThrows() {
        #expect(throws: DemoError.missingValue(argument: "-MidgarDemoScene")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemo", "daily", "-MidgarDemoScene"], environment: [:])
        }
    }

    @Test func emptyArgumentValueThrows() {
        #expect(throws: DemoError.missingValue(argument: "-MidgarDemoLocale")) {
            try DemoLaunch.parse(arguments: ["-MidgarDemo", "daily", "-MidgarDemoLocale", ""], environment: [:])
        }
    }

    @Test func keysSpellTheirArgumentAndEnvironmentNames() {
        #expect(DemoLaunch.Key.world.argument == "-MidgarDemo")
        #expect(DemoLaunch.Key.scene.argument == "-MidgarDemoScene")
        #expect(DemoLaunch.Key.date.argument == "-MidgarDemoDate")
        #expect(DemoLaunch.Key.locale.argument == "-MidgarDemoLocale")
        #expect(DemoLaunch.Key.allCases.map(\.environmentName) == ["MIDGAR_DEMO", "MIDGAR_DEMO_SCENE", "MIDGAR_DEMO_DATE", "MIDGAR_DEMO_LOCALE"])
    }

    @Test func currentReadsTheTestProcessWithoutDemoKeys() throws {
        #expect(try !DemoLaunch.current.isEnabled)
    }
}
