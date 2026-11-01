import Foundation
import Testing
@testable import MidgarCommerce

/// Keeps the offer state in memory. `lock` guards `state`.
final class MemoryOfferStorage: MidgarOfferStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state = MidgarOfferState()

    func load() -> MidgarOfferState { lock.withLock { state } }

    func save(_ state: MidgarOfferState) -> Bool {
        lock.withLock { self.state = state }
        return true
    }

    var saved: MidgarOfferState { lock.withLock { state } }
}

private let day: TimeInterval = 86_400

private struct OfferRig {
    let storage = MemoryOfferStorage()
    let clock = TestClock()
    let policy: MidgarOfferPolicy

    init(firstOfferAfter: Int = 1, laterOfferEvery: Int = 3) {
        let clock = clock
        policy = MidgarOfferPolicy(
            storage: storage, firstOfferAfter: firstOfferAfter, laterOfferEvery: laterOfferEvery, clock: { clock.now })
    }

    /// A new launch over the same saved state.
    func relaunched() -> MidgarOfferPolicy {
        let clock = clock
        return MidgarOfferPolicy(
            storage: storage, firstOfferAfter: policy.firstOfferAfter, laterOfferEvery: policy.laterOfferEvery,
            clock: { clock.now })
    }
}

@Suite struct OfferPolicyTests {
    @Test func theFirstValueMomentOffers() {
        let rig = OfferRig()

        #expect(rig.policy.evaluate() == .hold(.notEnoughValueYet))
        #expect(rig.policy.noteValue(isOwned: false))
    }

    @Test func aLaterFirstOfferWaitsForItsValueMoments() {
        let rig = OfferRig(firstOfferAfter: 2)

        #expect(rig.policy.noteValue(isOwned: false) == false)
        #expect(rig.policy.noteValue(isOwned: false))
    }

    @Test func anOwnerIsNeverOffered() {
        let rig = OfferRig()

        #expect(rig.policy.noteValue(isOwned: true) == false)
        #expect(rig.policy.evaluate() == .hold(.alreadyOwned))
        #expect(rig.relaunched().noteValue(isOwned: false) == false)
    }

    @Test func aPurchaseEndsTheOffers() {
        let rig = OfferRig()
        rig.policy.noteOwned()

        #expect(rig.policy.noteValue(isOwned: false) == false)
        #expect(rig.storage.saved.owned)
    }

    @Test func oneOfferPerSession() {
        let rig = OfferRig(laterOfferEvery: 1)
        #expect(rig.policy.noteValue(isOwned: false))
        rig.policy.noteOffered()
        rig.clock.advance(10 * day)

        #expect(rig.policy.noteValue(isOwned: false) == false)
        #expect(rig.policy.evaluate() == .hold(.offeredThisSession))
    }

    @Test func aLaterOfferNeedsMoreValueAndDaysAfterTheLast() {
        let rig = OfferRig()
        #expect(rig.policy.noteValue(isOwned: false))
        rig.policy.noteOffered()
        let next = rig.relaunched()

        #expect(next.noteValue(isOwned: false) == false)
        #expect(next.noteValue(isOwned: false) == false)
        #expect(next.noteValue(isOwned: false) == false)
        #expect(next.evaluate() == .hold(.offeredRecently))
        rig.clock.advance(3 * day)
        #expect(next.evaluate() == .offer)
    }

    @Test func atMostThreeOffersInAll() {
        let rig = OfferRig(laterOfferEvery: 1)
        for _ in 0..<MidgarOfferPolicy.maximumOffers {
            let policy = rig.relaunched()
            #expect(policy.noteValue(isOwned: false))
            policy.noteOffered()
            rig.clock.advance(4 * day)
        }
        let last = rig.relaunched()

        #expect(last.noteValue(isOwned: false) == false)
        #expect(last.evaluate() == .hold(.offersUsedUp))
        #expect(last.offers == 3)
    }

    @Test func theStateSurvivesInAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("offer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = MidgarOfferFileStorage(appID: "app/../x", directory: directory)
        let policy = MidgarOfferPolicy(storage: storage)
        #expect(policy.noteValue(isOwned: false))
        policy.noteOffered()

        #expect(storage.fileURL.lastPathComponent == "offer-app____x.json")
        #expect(storage.load().offers == 1)
        #expect(storage.load().valueMomentsAtLastOffer == 1)
    }
}
