import Testing
import MidgarUI

@Suite struct MidgarUITests {
    @Test func moduleBuilds() {
        #expect(MidgarUIModule.name == "MidgarUI")
    }
}
