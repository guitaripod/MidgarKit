import Testing
import MidgarKit

@Suite struct MidgarKitUmbrellaTests {
    @Test func everyProductIsReachableThroughTheUmbrella() {
        #expect(MidgarCoreModule.name == "MidgarCore")
        #expect(MidgarCommerceModule.name == "MidgarCommerce")
        #expect(MidgarCommerceUIModule.name == "MidgarCommerceUI")
        #expect(MidgarAccountModule.name == "MidgarAccount")
        #expect(MidgarUIModule.name == "MidgarUI")
        #expect(MidgarIntelligenceModule.name == "MidgarIntelligence")
        #expect(MidgarDemoModule.name == "MidgarDemo")
    }

    @Test func portalPublicAPIIsReachableThroughTheUmbrella() {
        let config = MidgarConfig(placement: "settings")
        #expect(config.placement == "settings")
        #expect(MidgarConfig.default.enableTelemetry)
    }
}
