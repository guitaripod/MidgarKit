import Foundation
import Testing
@testable import MidgarCore

private struct Empty: Codable, Sendable {}

@Suite struct MidgarModelRegionTests {
    private func makeRegion() -> MidgarModelRegion {
        let suite = "MidgarModelRegionTests." + UUID().uuidString
        return MidgarModelRegion(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func modelsAreAvailableUntilTheGatewayAnswers() {
        #expect(makeRegion().modelsAvailable)
    }

    @Test func refreshAsksTheRegionRouteAndRemembersTheAnswer() async {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"models\":false}"), .json(200, "{\"models\":true}")])
        let region = makeRegion()
        let client = makeStubClient(host)

        #expect(await region.refresh(client: client) == false)
        #expect(region.modelsAvailable == false)
        #expect(host.requests.first?.url.path == "/v1/region")
        #expect(host.requests.first?.method == "GET")

        #expect(await region.refresh(client: client) == true)
        #expect(region.modelsAvailable)
    }

    @Test func aFailedRefreshKeepsTheLastAnswer() async {
        let host = HTTPTestHost()
        host.enqueue([.json(200, "{\"models\":false}"), .failing(.notConnectedToInternet), .failing(.notConnectedToInternet), .failing(.notConnectedToInternet)])
        let region = makeRegion()
        let client = makeStubClient(host)

        _ = await region.refresh(client: client)
        #expect(await region.refresh(client: client) == false)
    }

    @Test func a451FromAModelRouteMeansModelsAreUnavailable() {
        let region = makeRegion()
        #expect(region.note(statusCode: 500) == false)
        #expect(region.modelsAvailable)
        #expect(region.note(statusCode: 451))
        #expect(region.modelsAvailable == false)
    }

    @Test func aRefusalReachesTheAppAsTheRegionMessage() async {
        let host = HTTPTestHost()
        host.enqueue([.json(451, "{\"error\":{\"message\":\"This is not available in your region. Nothing was charged.\",\"type\":\"unavailable_in_region\",\"code\":\"unavailable_in_region\"}}")])
        let client = makeStubClient(host)
        let region = makeRegion()

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "intelligence", path: "v1/run/chat.completion", method: .post, body: Empty()))
        }

        #expect(error?.serverCode == "unavailable_in_region")
        #expect(error?.isTransient == false)
        #expect(error?.errorDescription == MidgarModelRegion.unavailableMessage)
        #expect(MidgarModelRegion.unavailableMessage == "Not available in your region.")
        #expect(region.note(error!))
        #expect(region.modelsAvailable == false)
    }

    @Test func otherErrorsAreNotRefusals() {
        let region = makeRegion()
        #expect(region.note(MidgarHTTPError.server(status: 503, code: nil, message: "down")) == false)
        #expect(region.note(MidgarHTTPError.offline) == false)
        #expect(region.note(CancellationError()) == false)
        #expect(region.modelsAvailable)
    }

    @Test func aFlipPostsTheChangeOnce() {
        let region = makeRegion()
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: MidgarModelRegion.didChangeNotification, object: region, queue: nil) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        region.note(statusCode: 451)
        region.note(statusCode: 451)
        #expect(posts == 1)
    }
}
