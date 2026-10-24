import Foundation
import Testing
@testable import MidgarCredits

@Suite struct CreditsAllowanceTests {
    @Test func weeklyBucketsBecomeAllowancesSortedByIdWithTheirResetDate() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .json(200, """
        {"balance":12,"currency":"credits","weekly":{
          "reading.v2":{"limit":3,"remaining":2,"resets_at":"2026-10-12T00:00:00Z"},
          "chat.haiku":{"limit":10,"remaining":0,"resets_at":"2026-10-12T00:00:00Z"}
        }}
        """))

        let balance = try await h.credits.refresh()

        let reset = Date(timeIntervalSince1970: 1_791_763_200)
        #expect(balance.credits == 12)
        #expect(balance.allowances == [
            MidgarCreditsAllowance(id: "chat.haiku", remaining: 0, limit: 10, resetsAt: reset),
            MidgarCreditsAllowance(id: "reading.v2", remaining: 2, limit: 3, resetsAt: reset)
        ])
        #expect(await h.credits.balance?.allowances.count == 2)
    }

    @Test func aBalanceWithoutWeeklyBucketsHasNoAllowances() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .balance(42))

        let balance = try await h.credits.refresh()

        #expect(balance.credits == 42)
        #expect(balance.allowances.isEmpty)
    }

    @Test func aMalformedBucketIsSkippedAndTheBalanceStillReads() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .json(200, """
        {"balance":5,"currency":"credits","weekly":{
          "good":{"limit":3,"remaining":1,"resets_at":"2026-10-12T00:00:00Z"},
          "missing-remaining":{"limit":3,"resets_at":"2026-10-12T00:00:00Z"},
          "wrong-type":{"limit":"three","remaining":1},
          "not-an-object":7
        }}
        """))

        let balance = try await h.credits.refresh()

        #expect(balance.credits == 5)
        #expect(balance.allowances.map(\.id) == ["good"])
    }

    @Test func aWeeklyFieldThatIsNotAnObjectIsIgnored() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .json(200, #"{"balance":9,"currency":"credits","weekly":"soon"}"#))

        let balance = try await h.credits.refresh()

        #expect(balance.credits == 9)
        #expect(balance.allowances.isEmpty)
    }

    @Test func aBucketWithoutAResetDateOrWithANegativeRemainderIsKeptAndClamped() async throws {
        let h = CreditsHarness()
        h.gateway.script("balance", .json(200, #"{"balance":1,"weekly":{"a":{"limit":3,"remaining":-2},"b":{"limit":3,"remaining":1,"resets_at":"later"}}}"#))

        let balance = try await h.credits.refresh()

        #expect(balance.allowances == [
            MidgarCreditsAllowance(id: "a", remaining: 0, limit: 3, resetsAt: nil),
            MidgarCreditsAllowance(id: "b", remaining: 1, limit: 3, resetsAt: nil)
        ])
    }

    @Test func aChangedAllowanceIsAnEventEvenWhenTheCreditsStayTheSame() async throws {
        let h = CreditsHarness()
        let stream = await h.credits.events()
        h.gateway.script("balance", .json(200, #"{"balance":5,"weekly":{"a":{"limit":3,"remaining":3}}}"#))
        _ = try await h.credits.refresh()
        h.gateway.script("balance", .json(200, #"{"balance":5,"weekly":{"a":{"limit":3,"remaining":2}}}"#))
        _ = try await h.credits.refresh()
        await h.credits.stop()

        var events: [MidgarCreditsEvent] = []
        for await event in stream {
            events.append(event)
        }
        #expect(events.count == 2)
    }

    @Test func theExistingInitializerStillBuildsABalanceWithoutAllowances() {
        let balance = MidgarCreditsBalance(credits: 3, updatedAt: creditsEpoch)

        #expect(balance.allowances.isEmpty)
    }
}
