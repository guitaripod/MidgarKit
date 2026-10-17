import Foundation
import Testing
@testable import MidgarCommerce

/// Keeps the review state in memory. `lock` guards `state`.
final class MemoryReviewStorage: MidgarReviewStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state = MidgarReviewState()

    func load() -> MidgarReviewState { lock.withLock { state } }

    func save(_ state: MidgarReviewState) -> Bool {
        lock.withLock { self.state = state }
        return true
    }

    var saved: MidgarReviewState { lock.withLock { state } }
}

private let day: TimeInterval = 86_400

/// A policy that has been installed long enough, run often enough and had a good moment, so each test spoils exactly one rule.
private struct ReviewRig {
    let storage = MemoryReviewStorage()
    let clock = TestClock()
    let policy: MidgarReviewPolicy

    init(version: String = "2.0", sessions: Int = 6, daysSinceInstall: Double = 10) {
        let storage = storage
        let clock = clock
        policy = MidgarReviewPolicy(storage: storage, appVersion: version, clock: { clock.now })
        clock.advance(daysSinceInstall * day)
        for _ in 0..<sessions {
            policy.beginSession()
        }
    }
}

@Suite struct ReviewPolicyTests {
    @Test func aPositiveMomentOnAnEstablishedInstallPrompts() {
        let rig = ReviewRig()

        #expect(rig.policy.noteSuccess())
        #expect(rig.policy.evaluate() == .prompt)
        #expect(rig.policy.shouldPrompt())
    }

    @Test func withoutAPositiveMomentNothingPrompts() {
        let rig = ReviewRig()

        #expect(rig.policy.evaluate() == .hold(.noPositiveMoment))
        #expect(rig.policy.shouldPrompt() == false)
    }

    @Test func neverInTheFirstThreeDays() {
        let rig = ReviewRig(daysSinceInstall: 2.9)

        #expect(rig.policy.noteSuccess() == false)
        #expect(rig.policy.evaluate() == .hold(.tooSoonAfterInstall))

        rig.clock.advance(0.1 * day)

        #expect(rig.policy.evaluate() == .prompt)
    }

    @Test func neverInTheFirstFiveSessions() {
        let rig = ReviewRig(sessions: 5)

        #expect(rig.policy.noteSuccess() == false)
        #expect(rig.policy.evaluate() == .hold(.tooFewSessions))

        rig.policy.beginSession()

        #expect(rig.policy.evaluate() == .prompt)
    }

    @Test func neverWithin120DaysOfThePreviousPrompt() {
        let rig = ReviewRig(version: "2.0")
        rig.policy.noteSuccess()
        rig.policy.notePrompted()
        let nextVersion = MidgarReviewPolicy(storage: rig.storage, appVersion: "2.1", clock: { rig.clock.now })
        nextVersion.noteSuccess()

        #expect(nextVersion.evaluate() == .hold(.promptedRecently))

        rig.clock.advance(119 * day)

        #expect(nextVersion.evaluate() == .hold(.promptedRecently))

        rig.clock.advance(1 * day)

        #expect(nextVersion.evaluate() == .prompt)
    }

    @Test func neverOnTheAppVersionThatAlreadyPrompted() {
        let rig = ReviewRig(version: "2.0")
        rig.policy.noteSuccess()
        rig.policy.notePrompted()
        rig.clock.advance(400 * day)
        rig.policy.noteSuccess()

        #expect(rig.policy.evaluate() == .hold(.versionAlreadyPrompted))
    }

    @Test func aNewVersionMayPromptOnceTheIntervalHasPassed() {
        let rig = ReviewRig(version: "2.0")
        rig.policy.noteSuccess()
        rig.policy.notePrompted()
        rig.clock.advance(121 * day)
        let nextVersion = MidgarReviewPolicy(storage: rig.storage, appVersion: "2.1", clock: { rig.clock.now })

        #expect(nextVersion.noteSuccess())
    }

    @Test func notRightAfterAPurchaseFailure() {
        let rig = ReviewRig()
        rig.policy.notePurchaseFailure()
        rig.policy.noteSuccess()

        #expect(rig.policy.evaluate() == .hold(.recentPurchaseTrouble))

        rig.clock.advance(6.9 * day)

        #expect(rig.policy.evaluate() == .hold(.recentPurchaseTrouble))

        rig.clock.advance(0.1 * day)

        #expect(rig.policy.evaluate() == .prompt)
    }

    @Test func notRightAfterARefund() {
        let rig = ReviewRig()
        rig.policy.noteRefund()
        rig.policy.noteSuccess()

        #expect(rig.policy.evaluate() == .hold(.recentPurchaseTrouble))

        rig.clock.advance(7 * day)

        #expect(rig.policy.evaluate() == .prompt)
    }

    @Test func promptingConsumesThePositiveMoment() {
        let rig = ReviewRig()
        rig.policy.noteSuccess()
        rig.policy.notePrompted()

        #expect(rig.policy.evaluate() == .hold(.noPositiveMoment))
    }

    @Test func aPositiveMomentBelongsToTheSessionThatReportedIt() {
        let rig = ReviewRig(daysSinceInstall: 1)
        rig.policy.noteSuccess()
        rig.clock.advance(5 * day)

        let relaunched = MidgarReviewPolicy(storage: rig.storage, appVersion: "2.0", clock: { rig.clock.now })

        #expect(relaunched.evaluate() == .hold(.noPositiveMoment))
    }

    @Test func theFirstLaunchIsRecordedOnceAndSessionsAreCounted() {
        let rig = ReviewRig(sessions: 2, daysSinceInstall: 0)
        let first = rig.storage.saved.firstLaunch

        rig.clock.advance(3 * day)
        let relaunched = MidgarReviewPolicy(storage: rig.storage, appVersion: "2.0", clock: { rig.clock.now })
        relaunched.beginSession()

        #expect(first == commerceEpoch)
        #expect(rig.storage.saved.firstLaunch == first)
        #expect(rig.storage.saved.sessions == 3)
    }

    @Test func everyRuleSurvivesARelaunchThroughTheFileStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = TestClock()
        let storage = MidgarReviewFileStorage(appID: "app-test", directory: directory)
        let first = MidgarReviewPolicy(storage: storage, appVersion: "2.0", clock: { clock.now })
        clock.advance(10 * day)
        for _ in 0..<6 {
            first.beginSession()
        }
        first.noteSuccess()
        first.notePrompted()
        first.notePurchaseFailure()
        first.noteRefund()

        let second = MidgarReviewPolicy(storage: MidgarReviewFileStorage(appID: "app-test", directory: directory), appVersion: "2.0", clock: { clock.now })
        let saved = MidgarReviewFileStorage(appID: "app-test", directory: directory).load()

        #expect(saved.sessions == 6)
        #expect(saved.firstLaunch == commerceEpoch)
        #expect(saved.lastPrompt == commerceEpoch.addingTimeInterval(10 * day))
        #expect(saved.lastPromptedVersion == "2.0")
        #expect(saved.lastPurchaseFailure != nil)
        #expect(saved.lastRefund != nil)
        second.noteSuccess()
        #expect(second.evaluate() == .hold(.versionAlreadyPrompted))
    }

    @Test func eachAppKeepsItsOwnFile() {
        let directory = URL(fileURLWithPath: "/tmp/reviews", isDirectory: true)

        let one = MidgarReviewFileStorage(appID: "psywave", directory: directory)
        let other = MidgarReviewFileStorage(appID: "pay-day", directory: directory)
        let hostile = MidgarReviewFileStorage(appID: "../escape", directory: directory)

        #expect(one.fileURL.lastPathComponent == "review-psywave.json")
        #expect(other.fileURL.lastPathComponent == "review-pay-day.json")
        #expect(hostile.fileURL.deletingLastPathComponent().path == "/tmp/reviews")
    }

    @Test func aCorruptFileStartsFresh() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("review-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storage = MidgarReviewFileStorage(appID: "app-test", directory: directory)
        try Data("{not json".utf8).write(to: storage.fileURL)

        #expect(storage.load() == MidgarReviewState())
    }
}
