import Testing
import MidgarDemo

@Suite struct MidgarDemoTests {
    @Test func moduleBuilds() {
        #expect(MidgarDemoModule.name == "MidgarDemo")
    }
}
