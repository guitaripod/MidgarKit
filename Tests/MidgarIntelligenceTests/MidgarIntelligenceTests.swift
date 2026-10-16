import Testing
import MidgarIntelligence

@Suite struct MidgarIntelligenceTests {
    @Test func moduleBuilds() {
        #expect(MidgarIntelligenceModule.name == "MidgarIntelligence")
    }

    @Test func foundationModelsFlagMatchesTheSDK() {
        #if canImport(FoundationModels)
        #expect(MidgarIntelligenceModule.hasFoundationModels)
        #else
        #expect(!MidgarIntelligenceModule.hasFoundationModels)
        #endif
    }
}
