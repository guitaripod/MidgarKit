import Testing
import MidgarCommerce

@Suite struct MidgarCommerceTests {
    @Test func moduleBuilds() {
        #expect(MidgarCommerceModule.name == "MidgarCommerce")
    }
}
