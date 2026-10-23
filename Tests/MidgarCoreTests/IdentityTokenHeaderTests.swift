import Foundation
import Testing
@testable import MidgarCore

private struct Unavailable: Error {}

@Suite struct AsyncTimeoutTests {
    @Test func returnsTheValueWhenTheOperationFinishesInTime() async throws {
        let value = try await AsyncTimeout.run(for: .seconds(5)) { 42 }

        #expect(value == 42)
    }

    @Test func rethrowsTheOperationsOwnError() async {
        await #expect(throws: Unavailable.self) {
            try await AsyncTimeout.run(for: .seconds(5)) { throw Unavailable() }
        }
    }

    @Test func expiresWithoutWaitingForAnOperationThatNeverReturns() async {
        let clock = ContinuousClock()
        let started = clock.now

        await #expect(throws: AsyncTimeout.Expired.self) {
            try await AsyncTimeout.run(for: .milliseconds(100)) {
                await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
            }
        }

        #expect(started.duration(to: clock.now) < .seconds(3))
    }
}

@Suite struct IdentityTokenHeaderTests {
    @Test func answersWithTheTokenHeaderWhenTheIdentityIsQuickEnough() async throws {
        let harness = try IdentityHarness()
        harness.enqueue(.json(201, sessionJSON(
            midgarId: "id-1", accessToken: freshToken(), refreshToken: "r", extra: ["credential": "CRED-H"]
        )))

        let header = await harness.identity.midgarTokenHeader(within: .seconds(5))

        #expect(header?.name == "X-Midgar-Token")
        #expect(header?.value == freshToken())
    }

    @Test func answersNilWhenTheIdentityIsUnavailable() async throws {
        let harness = try IdentityHarness()
        harness.enqueue(.failing(.notConnectedToInternet))

        let header = await harness.identity.midgarTokenHeader(within: .seconds(5))

        #expect(header == nil)
    }

    @Test func answersNilAtTheTimeoutWhenTheIdentityHangs() async {
        let clock = ContinuousClock()
        let started = clock.now

        let header = await MidgarIdentity.tokenHeader(within: .milliseconds(100)) {
            await withCheckedContinuation { (_: CheckedContinuation<String, Never>) in }
        }

        #expect(header == nil)
        #expect(started.duration(to: clock.now) < .seconds(3))
    }

    @Test func answersNilForAnEmptyToken() async {
        let header = await MidgarIdentity.tokenHeader(within: .seconds(5)) { "" }

        #expect(header == nil)
    }

    @Test func carriesTheTokenUnchanged() async {
        let header = await MidgarIdentity.tokenHeader(within: .seconds(5)) { "abc.def.ghi" }

        #expect(header?.name == "X-Midgar-Token")
        #expect(header?.value == "abc.def.ghi")
    }
}
