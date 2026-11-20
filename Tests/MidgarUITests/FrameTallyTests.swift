import Testing
@testable import MidgarUI

@Suite struct FrameTallyTests {
    private static let sixty = 1.0 / 60
    private static let oneTwenty = 1.0 / 120

    @Test func aSteadyDisplayHasNoLateFrames() {
        var tally = MidgarFrameTally()
        for _ in 0..<120 { tally.note(wait: Self.sixty, frame: Self.sixty) }
        #expect(tally.frames == 120)
        #expect(tally.late == 0)
        #expect(tally.noticeable == 0)
        #expect(tally.summary == "120 frames, worst wait 17 ms, 0 late, 0 of 50 ms or more")
    }

    @Test func aDroppedFrameIsLateWithoutBeingNoticeable() {
        var tally = MidgarFrameTally()
        let felt = tally.note(wait: Self.sixty * 2, frame: Self.sixty)
        #expect(!felt)
        #expect(tally.late == 1)
        #expect(tally.noticeable == 0)
    }

    @Test func aWaitAPersonCanFeelIsCountedAndReported() {
        var tally = MidgarFrameTally()
        tally.note(wait: Self.sixty, frame: Self.sixty)
        let felt = tally.note(wait: 0.076, frame: Self.sixty)
        #expect(felt)
        #expect(tally.late == 1)
        #expect(tally.noticeable == 1)
        #expect(tally.summary == "2 frames, worst wait 76 ms, 1 late, 1 of 50 ms or more")
    }

    @Test func lateIsMeasuredAgainstTheDisplaysOwnPace() {
        var fast = MidgarFrameTally()
        fast.note(wait: Self.sixty, frame: Self.oneTwenty)
        #expect(fast.late == 1)
        var slow = MidgarFrameTally()
        slow.note(wait: Self.sixty, frame: Self.sixty)
        #expect(slow.late == 0)
    }

    @Test func theThresholdItselfCounts() {
        var tally = MidgarFrameTally()
        let atThreshold = tally.note(wait: MidgarFrameTally.noticeableWait, frame: Self.sixty)
        let justUnder = tally.note(wait: MidgarFrameTally.noticeableWait - 0.001, frame: Self.sixty)
        #expect(atThreshold)
        #expect(!justUnder)
        #expect(tally.noticeable == 1)
    }
}
