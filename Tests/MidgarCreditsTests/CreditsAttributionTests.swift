import Foundation
import Testing
import MidgarCore
@testable import MidgarCredits

@Suite struct CreditsAttributionTests {
    @Test func theTokenIsPostedOnceToTheAttributionRouteWithAICreditsBody() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("attributed"))

        let result = await h.credits.reportAdAttributionOnce()

        #expect(result == .settled(.attributed))
        #expect(result.isPaidInstall)
        let request = try #require(h.gateway.requests.first)
        #expect(h.gateway.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.path == "/v1/intelligence/v1/attribution")
        #expect(request.json as? [String: String] == ["attribution_token": fakeAttributionToken])
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(h.logs.lines.allSatisfy { !$0.contains(fakeAttributionToken) })
    }

    @Test func aSettledInstallIsNeverReportedAgainByThisOrALaterLaunch() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("organic"))

        _ = await h.credits.reportAdAttributionOnce()
        let again = await h.credits.reportAdAttributionOnce()
        let relaunched = await h.relaunched().credits.reportAdAttributionOnce()

        #expect(again == .alreadySettled(.organic))
        #expect(relaunched == .alreadySettled(.organic))
        #expect(!relaunched.isPaidInstall)
        #expect(h.gateway.requests.count == 1)
        #expect(h.tokens.callCount == 1)
    }

    @Test func aDuplicateVerdictAlsoSettlesTheInstall() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("duplicate"))

        #expect(await h.credits.reportAdAttributionOnce() == .settled(.duplicate))
        #expect(await h.relaunched().credits.reportAdAttributionOnce() == .alreadySettled(.duplicate))
    }

    @Test func aNetworkFailureIsRetriedOnTheNextLaunch() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .failing(.notConnectedToInternet))

        let first = await h.credits.reportAdAttributionOnce()
        h.gateway.script("attribution", .attribution("attributed"))
        let second = await h.relaunched().credits.reportAdAttributionOnce()

        #expect(first == .deferred)
        #expect(second == .settled(.attributed))
        #expect(h.gateway.requests.count == 2)
        #expect(h.tokens.callCount == 2)
    }

    @Test func beingOfflineForManyLaunchesNeverGivesUpOnTheInstall() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .failing(.timedOut))
        for _ in 0..<8 {
            #expect(await h.relaunched().credits.reportAdAttributionOnce() == .deferred)
        }
        h.gateway.script("attribution", .attribution("attributed"))

        #expect(await h.relaunched().credits.reportAdAttributionOnce() == .settled(.attributed))
    }

    @Test func aTokenProviderThatThrowsSendsNothingAndCostsNothing() async throws {
        let h = CreditsHarness()
        h.tokens.set(.failing)
        h.gateway.script("attribution", .attribution("attributed"))

        for _ in 0..<8 {
            #expect(await h.relaunched().credits.reportAdAttributionOnce() == .noToken)
        }
        #expect(h.gateway.requests.isEmpty)

        h.tokens.set(.token(fakeAttributionToken))
        #expect(await h.relaunched().credits.reportAdAttributionOnce() == .settled(.attributed))
    }

    @Test func noTokenAndAShapeMakoWouldRefuseSendNothing() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("attributed"))

        h.tokens.set(.nothing)
        #expect(await h.credits.reportAdAttributionOnce() == .noToken)
        h.tokens.set(.token("short"))
        #expect(await h.credits.reportAdAttributionOnce() == .noToken)
        h.tokens.set(.token(String(repeating: "A", count: 15) + "!"))
        #expect(await h.credits.reportAdAttributionOnce() == .noToken)
        #expect(h.gateway.requests.isEmpty)
    }

    @Test func aLaunchTheAppDoesNotCallProductionCapturesAndSendsNothing() async throws {
        let h = CreditsHarness()
        h.production.set(false)
        h.gateway.script("attribution", .attribution("attributed"))

        let result = await h.credits.reportAdAttributionOnce()

        #expect(result == .skipped)
        #expect(h.tokens.callCount == 0)
        #expect(h.gateway.requests.isEmpty)
        h.production.set(true)
        #expect(await h.relaunched().credits.reportAdAttributionOnce() == .settled(.attributed))
    }

    @Test func aNativeRequestCarriesTheMidgarTokenAsTheOnlyCredential() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("attributed"))

        _ = await h.credits.reportAdAttributionOnce()

        let request = try #require(h.gateway.requests.first)
        #expect(request.headers["Authorization"] == "Bearer jwt-1")
        #expect(request.headers["X-Midgar-Token"] == nil)
        #expect(request.headers["X-App-ID"] == "app-test")
    }

    @Test func aLegacyRequestCarriesTheKeyAsTheBearerAndTheMidgarTokenBesideIt() async throws {
        let h = CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
        h.gateway.script("attribution", .attribution("attributed"))

        _ = await h.credits.reportAdAttributionOnce()

        let request = try #require(h.gateway.requests.first)
        #expect(request.headers["Authorization"] == "Bearer mk_legacy_key")
        #expect(request.headers["X-Midgar-Token"] == "jwt-1")
        #expect(request.headers["X-App-ID"] == "app-test")
    }

    @Test func aLegacyRequestWithoutAMidgarTokenIsNotSentWithTheKeyAlone() async throws {
        let h = CreditsHarness(legacyAPIKey: { "mk_legacy_key" })
        h.identity.set(nil)
        h.gateway.script("attribution", .attribution("attributed"))

        let result = await h.credits.reportAdAttributionOnce()

        #expect(result == .deferred)
        #expect(h.gateway.requests.isEmpty)
    }

    @Test func aPendingVerdictIsRetriedInTheSameLaunchAfterMakosDelay() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("pending", retryAfter: 5), .attribution("attributed"))

        let result = await h.credits.reportAdAttributionOnce()

        #expect(result == .settled(.attributed))
        #expect(h.gateway.requests.count == 2)
        #expect(h.sleeper.requested == [.seconds(5)])
    }

    @Test func aLongWaitIsLeftToTheNextLaunch() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("pending", retryAfter: 60))

        let result = await h.credits.reportAdAttributionOnce()

        #expect(result == .deferred)
        #expect(h.gateway.requests.count == 1)
        #expect(h.sleeper.requested.isEmpty)
    }

    @Test func aLaunchGivesUpAfterThreeSubmissionsOfAPendingToken() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("pending", retryAfter: 1))

        #expect(await h.credits.reportAdAttributionOnce() == .deferred)
        #expect(h.gateway.requests.count == 3)
    }

    @Test func anInvalidTokenIsNotFinalButFiveLaunchesWithoutAVerdictEndTheRetrying() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("invalid"))

        for _ in 0..<5 {
            #expect(await h.relaunched().credits.reportAdAttributionOnce() == .deferred)
        }
        let sixth = await h.relaunched().credits.reportAdAttributionOnce()

        #expect(sixth == .exhausted)
        #expect(h.gateway.requests.count == 5)
    }

    @Test func aServerFailureCountsAsALaunchAndIsRetriedLater() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .refused(500, "internal_error", "boom"))

        #expect(await h.credits.reportAdAttributionOnce() == .deferred)
        h.gateway.script("attribution", .attribution("attributed"))
        #expect(await h.relaunched().credits.reportAdAttributionOnce() == .settled(.attributed))
    }

    @Test func aStatusMakoAddsLaterIsReadAsPendingWithTheDefaultDelay() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("something-new"))

        #expect(await h.credits.reportAdAttributionOnce() == .deferred)
        #expect(h.gateway.requests.count == 3)
        #expect(h.sleeper.requested == [.seconds(5), .seconds(5)])
    }

    @Test func callersAtTheSameTimeShareOneSubmission() async throws {
        let h = CreditsHarness()
        h.gateway.script("attribution", .attribution("attributed"))

        async let first = h.credits.reportAdAttributionOnce()
        async let second = h.credits.reportAdAttributionOnce()
        _ = await (first, second)

        #expect(h.gateway.requests.count == 1)
    }
}
