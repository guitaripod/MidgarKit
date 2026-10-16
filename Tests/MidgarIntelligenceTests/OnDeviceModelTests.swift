import Foundation
import Testing
import MidgarIntelligence

@Suite struct OnDeviceModelTests {
    @Test func availabilityIsAlwaysAnswered() {
        let availability = MidgarOnDeviceModel().availability
        switch availability {
        case .available, .unavailable:
            break
        }
        #if !canImport(FoundationModels)
        #expect(availability == .unavailable(.platformUnsupported))
        #endif
    }

    @Test func anUnavailableModelThrowsItsReasonInsteadOfCallingTheSystem() async {
        let model = MidgarOnDeviceModel()
        guard case .unavailable(let reason) = model.availability else {
            return
        }
        await #expect(throws: MidgarIntelligenceError.onDeviceUnavailable(reason)) {
            try await model.respond(to: MidgarPrompt(text: "Hi"))
        }
        await #expect(throws: MidgarIntelligenceError.onDeviceUnavailable(reason)) {
            try await collect(model.streamResponse(to: MidgarPrompt(text: "Hi")))
        }
    }

    @Test func promptsWithImagesAreCloudOnly() {
        let image = MidgarPromptImage(data: Data(), mediaType: "image/png")
        #expect(MidgarPrompt(text: "x", images: [image]).effectiveRequirement == .cloudOnly)
        #expect(MidgarPrompt(text: "x").effectiveRequirement == .any)
    }
}
