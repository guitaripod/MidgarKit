import Testing
import MidgarCore

@Suite struct MidgarCoreTests {
    @Test func moduleBuilds() {
        #expect(MidgarCoreModule.name == "MidgarCore")
    }

    @Test func versionIsSemantic() {
        let parts = MidgarKitVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}
