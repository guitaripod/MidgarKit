import Foundation
import MidgarCore

/// What a frame watch counted over one stretch of a run: the frames that came, the ones that came late, and the longest the
/// display waited for the main thread. Kept apart from the display link so the arithmetic can be tested.
public struct MidgarFrameTally: Equatable, Sendable {
    /// A wait a person can feel as a stutter: three frames of a 60 Hz display.
    public static let noticeableWait: TimeInterval = 0.05

    /// How far past the display's own pace a frame may come before it counts as late.
    private static let lateBy = 1.5

    public private(set) var frames = 0
    /// Frames that came more than half a frame after the display's pace would have had them, so at least one was dropped.
    public private(set) var late = 0
    /// Waits of `noticeableWait` or more.
    public private(set) var noticeable = 0
    public private(set) var worstWait: TimeInterval = 0

    public init() {}

    /// Counts a frame that came `wait` after the one before it, on a display whose frames are `frame` apart, and returns whether
    /// the wait was one a person can feel.
    @discardableResult
    public mutating func note(wait: TimeInterval, frame: TimeInterval) -> Bool {
        frames += 1
        worstWait = max(worstWait, wait)
        if wait > frame * Self.lateBy { late += 1 }
        guard wait >= Self.noticeableWait else { return false }
        noticeable += 1
        return true
    }

    /// The stretch in one line for the log: "412 frames, worst wait 76 ms, 3 late, 1 of 50 ms or more".
    public var summary: String {
        let threshold = Self.milliseconds(Self.noticeableWait)
        return "\(frames) frames, worst wait \(Self.milliseconds(worstWait)) ms, \(late) late, \(noticeable) of \(threshold) ms or more"
    }

    static func milliseconds(_ time: TimeInterval) -> Int {
        Int((time * 1000).rounded())
    }
}

#if canImport(UIKit) && !os(watchOS)
import QuartzCore
import UIKit

/// Says how long the main thread kept the display waiting, in the app's own log, so a run on a real device ends with numbers
/// for whether a screen stuttered. A display link ticks with the screen, and a tick that comes late means the main thread was
/// busy for that long: every wait a person can feel is a log line as it happens, and `report` adds the count of the stretch
/// since the last report (`MidgarFrameTally`).
///
/// It is for debug launches on a device nobody is tapping, where Instruments is not attached: start it from the app's debug
/// launch switches, or call `startIfRequested` at launch inside `#if DEBUG` and pass `MIDGAR_FRAME_WATCH=<seconds>` in the
/// launch environment to have a report every that many seconds. Pull `Library/Logs` afterwards and read the `Frame` lines.
@MainActor
public final class MidgarFrameWatch: NSObject {
    public static let shared = MidgarFrameWatch()

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var tally = MidgarFrameTally()
    private var disregarded = 0
    private var reports: Task<Void, Never>?

    public var isRunning: Bool { link != nil }

    /// Starts counting. With `interval` the stretch is also reported and begun again at that pace, for a run nothing else
    /// divides into stretches.
    public func start(reportingEvery interval: TimeInterval? = nil) {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
        guard let interval, interval > 0 else { return }
        reports = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.report("the last \(MidgarFrameTally.milliseconds(interval)) ms")
            }
        }
    }

    /// Starts the watch when the launch environment has `MIDGAR_FRAME_WATCH=<seconds>`, reporting at that pace.
    public func startIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let interval = environment["MIDGAR_FRAME_WATCH"].flatMap(TimeInterval.init), interval > 0 else { return }
        start(reportingEvery: interval)
    }

    /// Logs the stretch that just ended and begins the next.
    public func report(_ stretch: String) {
        guard link != nil else { return }
        MidgarLog.notice("Frame watch, \(stretch): \(tally.summary)", category: .ui)
        tally = MidgarFrameTally()
    }

    /// Leaves out the wait that work the capture itself just did on the main thread, drawing a snapshot for one, is about
    /// to show up as. The first frame after such work can still carry the time it was due at, so the two that follow are
    /// not counted.
    public func disregardWhatJustRan() {
        disregarded = 2
    }

    public func stop() {
        reports?.cancel()
        reports = nil
        link?.invalidate()
        link = nil
        last = 0
        disregarded = 0
        tally = MidgarFrameTally()
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp }
        guard last > 0 else { return }
        guard disregarded == 0 else {
            disregarded -= 1
            return
        }
        let wait = link.timestamp - last
        guard tally.note(wait: wait, frame: link.targetTimestamp - link.timestamp) else { return }
        MidgarLog.notice("Frame wait \(MidgarFrameTally.milliseconds(wait)) ms", category: .ui)
    }
}
#endif
