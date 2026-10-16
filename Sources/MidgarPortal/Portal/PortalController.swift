import CoreGraphics
import Foundation
import QuartzCore

/// Which edges of the canvas are covered by chrome, so the honeycomb centres itself in what is
/// left instead of behind the header and the card.
struct PortalInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0
}

/// The platform-neutral brain of the portal canvas. UIKit and AppKit views feed it input and
/// frame callbacks; it owns the camera, decides what is focused, and tells the renderer what to
/// draw.
@MainActor
final class PortalController {
    static let focusDelay: TimeInterval = 0.5
    static let impressionDiameter: CGFloat = 40

    let renderer: PortalRenderer
    private(set) var layout: PortalLayout
    private(set) var camera: PortalCamera
    private(set) var focusedIndex = 0
    private(set) var size: CGSize = .zero
    private(set) var insets = PortalInsets()

    var onFocusChange: ((PortalCell) -> Void)?
    var onActivate: ((PortalCell) -> Void)?
    var onNeedsFrames: ((Bool) -> Void)?
    var onHaptic: (() -> Void)?
    var onSeen: ((String) -> Void)?
    var onFramesSettled: (() -> Void)?

    private var apps: [String: MidgarApp] = [:]
    private var rankedIDs: [String] = []
    private var hostBundleID: String?
    private var installed: Set<String> = []
    private var introStart: CFTimeInterval?
    private var lastTick: CFTimeInterval?
    private var pendingFocusID: String?
    private var lockedFocus: Int?
    private var seen = Set<String>()
    private var reduceMotion: Bool

    init(scale: CGFloat, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        let empty = PortalLayout.make(appIDs: [], pitch: 100)
        layout = empty
        camera = PortalCamera(bound: 100)
        renderer = PortalRenderer(layout: empty, scale: scale, reduceMotion: reduceMotion)
    }

    var focusedCell: PortalCell { layout.cells[min(focusedIndex, layout.cells.count - 1)] }

    func setReduceMotion(_ value: Bool) {
        reduceMotion = value
        renderer.setReduceMotion(value)
    }

    /// Replaces the catalog. `initialFocus` is the app the camera drifts to after the intro.
    func load(
        ranked: [MidgarApp],
        hostBundleID: String?,
        installed: Set<String>,
        initialFocus: String?
    ) {
        apps = Dictionary(uniqueKeysWithValues: ranked.map { ($0.appId, $0) })
        rankedIDs = ranked.map(\.appId)
        self.hostBundleID = hostBundleID
        self.installed = installed
        pendingFocusID = initialFocus
        rebuild(keepingCamera: false)
        renderer.setProgress(progressFraction())
    }

    func setInstalled(_ bundleIDs: Set<String>) {
        installed = bundleIDs
        renderer.setInstalled(bundleIDs)
        renderer.setProgress(progressFraction())
    }

    func setArtwork(_ image: CGImage, forApp appID: String) {
        renderer.setArtwork(image, forApp: appID)
    }

    func resize(to size: CGSize, insets: PortalInsets) {
        guard size.width > 0, size.height > 0 else { return }
        guard size != self.size || insets != self.insets else { return }
        let previousPitch = layout.pitch
        self.size = size
        self.insets = insets
        rebuild(keepingCamera: previousPitch > 0 && !rankedIDs.isEmpty, previousPitch: previousPitch)
    }

    /// Starts the opening animation: the cells spiral out of the core and the camera then drifts to
    /// the first app.
    func begin(at time: CFTimeInterval = CACurrentMediaTime()) {
        introStart = time
        lastTick = nil
        camera = PortalCamera(position: .zero, bound: camera.bound)
        focusedIndex = 0
        renderer.setFocus(0, animated: false)
        if reduceMotion, let id = pendingFocusID, let cell = layout.cell(forApp: id) {
            camera = PortalCamera(position: cell.world, bound: camera.bound)
            pendingFocusID = nil
            focus(on: cell, notify: true)
        }
        onNeedsFrames?(true)
        tick(now: time)
    }

    /// One display-link frame.
    func tick(now: CFTimeInterval) {
        let dt = lastTick.map { CGFloat(min(now - $0, 0.05)) } ?? 0
        lastTick = now
        let elapsed = introStart.map { now - $0 } ?? renderer.introDuration

        if let id = pendingFocusID, elapsed >= Self.focusDelay, let cell = layout.cell(forApp: id) {
            pendingFocusID = nil
            lockedFocus = cell.index
            focus(on: cell, notify: true)
            camera.glide(to: cell.world)
        }

        let moving = camera.step(dt)
        updateFocusFromCamera(moving: moving)
        renderer.render(camera: camera.position, intro: elapsed)

        let introDone = renderer.isIntroComplete(at: elapsed)
        if !moving && introDone && pendingFocusID == nil {
            reportSeenCells()
            onNeedsFrames?(false)
            onFramesSettled?()
        } else if introDone || moving {
            reportSeenCells()
        }
    }

    func pointerBegan() {
        lockedFocus = nil
        pendingFocusID = nil
        camera.beginDrag()
        onNeedsFrames?(true)
    }

    func pointerMoved(translation: CGPoint) {
        camera.drag(translation: translation)
    }

    func pointerEnded(velocity: CGPoint) {
        camera.endDrag(velocity: velocity, snapPoints: layout.snapPoints)
        onNeedsFrames?(true)
    }

    func scrolled(by delta: CGPoint) {
        lockedFocus = nil
        pendingFocusID = nil
        camera.nudge(by: delta)
        onNeedsFrames?(true)
    }

    func scrollEnded() {
        camera.settle(snapPoints: layout.snapPoints)
        onNeedsFrames?(true)
    }

    /// A tap on the canvas: a focused cell activates, any other cell comes to the centre first.
    func tap(at point: CGPoint) {
        guard let cell = renderer.cell(at: point) else { return }
        if cell.index == focusedIndex && !camera.isMoving {
            onActivate?(cell)
        } else {
            bringToCentre(cell)
        }
    }

    func activateFocused() {
        onActivate?(focusedCell)
    }

    func moveFocus(toward direction: CGVector) {
        guard let next = layout.neighbor(of: focusedCell, toward: direction) else { return }
        bringToCentre(next)
    }

    func bringToCentre(_ cell: PortalCell) {
        lockedFocus = cell.index
        pendingFocusID = nil
        focus(on: cell, notify: true)
        camera.glide(to: cell.world)
        onNeedsFrames?(true)
    }

    func bringToCentre(appID: String) {
        guard let cell = layout.cell(forApp: appID) else { return }
        bringToCentre(cell)
    }

    func frame(forCell index: Int) -> PortalCellFrame? {
        renderer.frames[index]
    }

    private func rebuild(keepingCamera: Bool, previousPitch: CGFloat = 0) {
        guard size.width > 0, size.height > 0 else { return }
        let usable = CGRect(
            x: 0, y: insets.top,
            width: max(size.width - insets.trailing, 160),
            height: max(size.height - insets.top - insets.bottom, 120)
        )
        let metrics = Self.metrics(for: usable)
        let newLayout = PortalLayout.make(appIDs: rankedIDs, pitch: metrics.pitch, rowStretch: metrics.rowStretch)
        let ratio = previousPitch > 0 ? metrics.pitch / previousPitch : 1
        let position = keepingCamera ? CGPoint(x: camera.position.x * ratio, y: camera.position.y * ratio) : .zero
        layout = newLayout
        camera = PortalCamera(position: position, bound: newLayout.reach + metrics.pitch * 0.4)
        renderer.configure(layout: newLayout, apps: apps, hostBundleID: hostBundleID, installed: installed)
        renderer.setViewport(
            size: size,
            center: CGPoint(x: usable.midX, y: usable.midY),
            halfExtent: metrics.halfExtent,
            diameter: metrics.diameter
        )
        let index = min(focusedIndex, newLayout.cells.count - 1)
        focusedIndex = index
        renderer.setFocus(index, animated: false)
        if keepingCamera {
            let snapped = newLayout.nearestCell(to: position)
            camera = PortalCamera(position: snapped.world, bound: camera.bound)
        }
    }

    static func metrics(for usable: CGRect) -> (pitch: CGFloat, diameter: CGFloat, rowStretch: CGFloat, halfExtent: CGSize) {
        let reference = min(usable.width, usable.height * 0.9)
        let pitch = max(92, min(190, reference * 0.375))
        let aspect = usable.height / max(usable.width, 1)
        return (
            pitch,
            pitch * 0.8,
            max(1, min(1.2, aspect * 0.85)),
            CGSize(width: usable.width / 2 * 1.08, height: usable.height / 2 * 1.04)
        )
    }

    private func updateFocusFromCamera(moving: Bool) {
        guard lockedFocus == nil || !moving else { return }
        if !moving, lockedFocus != nil { lockedFocus = nil }
        let nearest = layout.nearestCell(to: camera.position)
        guard nearest.index != focusedIndex else { return }
        focus(on: nearest, notify: true)
        if moving { onHaptic?() }
    }

    private func focus(on cell: PortalCell, notify: Bool) {
        let changed = cell.index != focusedIndex
        focusedIndex = cell.index
        renderer.setFocus(cell.index, animated: true)
        if changed && notify { onFocusChange?(cell) }
        if !changed && notify && cell.index == 0 { onFocusChange?(cell) }
    }

    private func reportSeenCells() {
        for cell in layout.cells {
            guard let id = cell.appID, !seen.contains(id), let frame = renderer.frames[cell.index] else { continue }
            guard frame.radius * 2 >= Self.impressionDiameter else { continue }
            let onScreen = frame.center.x > 0 && frame.center.x < size.width
                && frame.center.y > insets.top && frame.center.y < size.height - insets.bottom
            if onScreen {
                seen.insert(id)
                onSeen?(id)
            }
        }
    }

    private func progressFraction() -> CGFloat {
        let here = apps.values.filter { $0.runsOnThisDevice }
        guard !here.isEmpty else { return 0 }
        let owned = here.filter { installed.contains($0.bundleId.lowercased()) || $0.bundleId.lowercased() == hostBundleID?.lowercased() }
        return CGFloat(owned.count) / CGFloat(here.count)
    }
}
