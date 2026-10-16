import Foundation
import Testing
@testable import MidgarIntelligence

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

    @Test func snapshotsThatExtendTheTextBecomeDeltas() throws {
        var accumulator = OnDeviceSnapshotAccumulator()
        #expect(try accumulator.delta(for: "") == nil)
        #expect(try accumulator.delta(for: "Hel") == "Hel")
        #expect(try accumulator.delta(for: "Hel") == nil)
        #expect(try accumulator.delta(for: "Hello wor") == "lo wor")
        #expect(try accumulator.delta(for: "Hello world") == "ld")
        #expect(accumulator.emitted == "Hello world")
    }

    @Test func aSnapshotThatRewritesEarlierTextThrows() throws {
        var accumulator = OnDeviceSnapshotAccumulator()
        _ = try accumulator.delta(for: "Hello world")
        #expect(throws: MidgarIntelligenceError.onDeviceOutputRewritten) { try accumulator.delta(for: "Howdy world, friend") }
        #expect(throws: MidgarIntelligenceError.onDeviceOutputRewritten) { try accumulator.delta(for: "Hello") }
        #expect(throws: MidgarIntelligenceError.onDeviceOutputRewritten) { try accumulator.delta(for: "") }
    }
}
