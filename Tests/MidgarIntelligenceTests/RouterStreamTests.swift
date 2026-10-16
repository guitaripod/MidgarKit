import Foundation
import Testing
import MidgarIntelligence

@Suite struct RouterStreamTests {
    let prompt = MidgarPrompt(text: "hello")

    @Test func onDeviceDeltasPassThrough() async throws {
        let router = MidgarIntelligence(onDevice: FakeModel(), cloud: FakeModel(route: .cloud))
        #expect(try await collect(router.streamResponse(to: prompt)) == ["ans", "wer"])
    }

    @Test func anUnavailableModelStreamsFromTheCloud() async throws {
        let device = FakeModel(availability: .unavailable(.modelNotReady))
        let cloud = FakeModel(route: .cloud, deltas: ["cloud"])
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        #expect(try await collect(router.streamResponse(to: prompt)) == ["cloud"])
        #expect(await device.streamCalls.count == 0)
    }

    @Test func aFailureBeforeTheFirstDeltaFallsBack() async throws {
        let device = FakeModel(failure: FakeFailure())
        let cloud = FakeModel(route: .cloud, deltas: ["cloud"])
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        #expect(try await collect(router.streamResponse(to: prompt)) == ["cloud"])
    }

    @Test func aFailureAfterTextDoesNotSpliceTheCloudIn() async {
        let device = FakeModel(failure: FakeFailure(), failsBeforeDeltas: false)
        let cloud = FakeModel(route: .cloud, deltas: ["cloud"])
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        await #expect(throws: MidgarIntelligenceError.onDeviceFailed(errorType: "FakeFailure")) {
            try await collect(router.streamResponse(to: prompt))
        }
        #expect(await cloud.streamCalls.count == 0)
    }

    @Test func cancellationBeforeTheFirstDeltaDoesNotFallBack() async {
        let device = FakeModel(failure: CancellationError())
        let cloud = FakeModel(route: .cloud, deltas: ["cloud"])
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        await #expect(throws: CancellationError.self) {
            try await collect(router.streamResponse(to: prompt))
        }
        #expect(await cloud.streamCalls.count == 0)
    }

    @Test func killSwitchesApplyToStreams() async throws {
        let config = try killConfig("intelligence")
        let router = MidgarIntelligence(onDevice: FakeModel(), cloud: FakeModel(route: .cloud), config: { config })
        await #expect(throws: MidgarIntelligenceError.disabled) {
            try await collect(router.streamResponse(to: prompt))
        }
    }
}
