import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import MidgarIntelligence

@Suite struct RouterTests {
    let prompt = MidgarPrompt(text: "hello")

    @Test func availableOnDeviceAnswersWithoutTouchingTheCloud() async throws {
        let device = FakeModel()
        let cloud = FakeModel(route: .cloud)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        let completion = try await router.respond(to: prompt)
        #expect(completion.route == .onDevice)
        #expect(completion.creditsCharged == nil)
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test(arguments: [
        MidgarOnDeviceUnavailableReason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .platformUnsupported,
        .operatingSystemTooOld,
        .unknown
    ])
    func unavailableOnDeviceGoesToTheCloud(reason: MidgarOnDeviceUnavailableReason) async throws {
        let device = FakeModel(availability: .unavailable(reason))
        let cloud = FakeModel(route: .cloud)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        let completion = try await router.respond(to: prompt)
        #expect(completion.route == .cloud)
        #expect(completion.creditsCharged == 3)
        #expect(await device.respondCalls.count == 0)
    }

    @Test func cloudOnlyRequirementSkipsAnAvailableOnDeviceModel() async throws {
        let device = FakeModel()
        let router = MidgarIntelligence(onDevice: device, cloud: FakeModel(route: .cloud))
        let completion = try await router.respond(to: MidgarPrompt(text: "long", requirement: .cloudOnly))
        #expect(completion.route == .cloud)
        #expect(await device.respondCalls.count == 0)
    }

    @Test func anImageForcesTheCloud() async throws {
        let device = FakeModel()
        let router = MidgarIntelligence(onDevice: device, cloud: FakeModel(route: .cloud))
        let image = MidgarPromptImage(data: Data([1, 2, 3]), mediaType: "image/png")
        let completion = try await router.respond(to: MidgarPrompt(text: "what is this", images: [image]))
        #expect(completion.route == .cloud)
        #expect(await device.respondCalls.count == 0)
    }

    @Test func aModelFailureFallsBackToTheCloud() async throws {
        let device = FakeModel(failure: FakeFailure())
        let cloud = FakeModel(route: .cloud)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        let completion = try await router.respond(to: prompt)
        #expect(completion.route == .cloud)
        #expect(await device.respondCalls.count == 1)
        #expect(await cloud.respondCalls.count == 1)
    }

    @Test func cancellationDoesNotFallBack() async {
        let device = FakeModel(failure: CancellationError())
        let cloud = FakeModel(route: .cloud)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        await #expect(throws: CancellationError.self) {
            try await router.respond(to: prompt)
        }
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test func aCancelledURLErrorDoesNotFallBack() async {
        let device = FakeModel(failure: URLError(.cancelled))
        let cloud = FakeModel(route: .cloud)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        await #expect(throws: CancellationError.self) {
            try await router.respond(to: prompt)
        }
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test func theCloudErrorSurfacesWhenBothRoutesFail() async {
        let device = FakeModel(failure: FakeFailure())
        let cloud = FakeModel(route: .cloud, failure: MidgarIntelligenceError.needsCredits)
        let router = MidgarIntelligence(onDevice: device, cloud: cloud)
        await #expect(throws: MidgarIntelligenceError.needsCredits) {
            try await router.respond(to: prompt)
        }
    }

    @Test func killingIntelligenceThrowsDisabledWithoutCallingAnyModel() async throws {
        let device = FakeModel()
        let cloud = FakeModel(route: .cloud)
        let config = try killConfig("intelligence")
        let router = MidgarIntelligence(onDevice: device, cloud: cloud, config: { config })
        await #expect(throws: MidgarIntelligenceError.disabled) {
            try await router.respond(to: prompt)
        }
        #expect(await device.respondCalls.count == 0)
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test func killingTheCloudKeepsAnswersOnDevice() async throws {
        let device = FakeModel()
        let cloud = FakeModel(route: .cloud)
        let config = try killConfig("intelligence.cloud")
        let router = MidgarIntelligence(onDevice: device, cloud: cloud, config: { config })
        #expect(try await router.respond(to: prompt).route == .onDevice)
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test func killingTheCloudRefusesACloudOnlyPrompt() async throws {
        let config = try killConfig("intelligence.cloud")
        let router = MidgarIntelligence(onDevice: FakeModel(), cloud: FakeModel(route: .cloud), config: { config })
        await #expect(throws: MidgarIntelligenceError.cloudDisabled) {
            try await router.respond(to: MidgarPrompt(text: "x", requirement: .cloudOnly))
        }
    }

    @Test func killingTheCloudWithAnUnavailableModelReportsTheReason() async throws {
        let device = FakeModel(availability: .unavailable(.appleIntelligenceNotEnabled))
        let config = try killConfig("intelligence.cloud")
        let router = MidgarIntelligence(onDevice: device, cloud: FakeModel(route: .cloud), config: { config })
        await #expect(throws: MidgarIntelligenceError.onDeviceUnavailable(.appleIntelligenceNotEnabled)) {
            try await router.respond(to: prompt)
        }
    }

    @Test func killingTheCloudSurfacesAnOnDeviceFailureInsteadOfFallingBack() async throws {
        let cloud = FakeModel(route: .cloud)
        let config = try killConfig("intelligence.cloud")
        let router = MidgarIntelligence(onDevice: FakeModel(failure: FakeFailure()), cloud: cloud, config: { config })
        await #expect(throws: MidgarIntelligenceError.onDeviceFailed(errorType: "FakeFailure")) {
            try await router.respond(to: prompt)
        }
        #expect(await cloud.respondCalls.count == 0)
    }

    @Test func aKillSwitchThatArrivesLaterTakesEffectOnTheNextCall() async throws {
        let holder = ConfigHolder()
        let router = MidgarIntelligence(onDevice: FakeModel(), cloud: FakeModel(route: .cloud), config: { holder.value })
        #expect(try await router.respond(to: prompt).route == .onDevice)
        holder.value = try killConfig("intelligence")
        await #expect(throws: MidgarIntelligenceError.disabled) {
            try await router.respond(to: prompt)
        }
    }
}
