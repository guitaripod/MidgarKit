import Testing
import MidgarAccount

@Suite struct MidgarAccountTests {
    @Test func moduleBuilds() {
        #expect(MidgarAccountModule.name == "MidgarAccount")
    }
}
