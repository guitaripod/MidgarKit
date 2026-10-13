#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import QuartzCore

/// The portal canvas on macOS. Mouse drags, trackpad scrolls and the arrow keys all move the same
/// camera the touch version does; the layers are shared with iOS through ``PortalRenderer``.
@MainActor
final class PortalCanvasView: NSView {
    let controller: PortalController
    var insets = PortalInsets() {
        didSet { if insets != oldValue { needsLayout = true } }
    }
    var onAccessibilityActivate: ((PortalCell) -> Void)?
    var onCancel: (() -> Void)?

    private var displayLink: AnyObject?
    private var fallbackTimer: Timer?
    private var dragOrigin: CGPoint = .zero
    private var dragSamples: [(time: TimeInterval, point: CGPoint)] = []
    private var didDrag = false
    private var didBegin = false
    private var scrollIdle: Timer?
    private var apps: [String: MidgarApp] = [:]

    override init(frame: NSRect) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        controller = PortalController(scale: scale, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(controller.renderer.rootLayer)
        wireController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            stopFrames()
            return
        }
        window.makeFirstResponder(self)
        layoutSubtreeIfNeeded()
        if !didBegin {
            didBegin = true
            controller.begin()
        }
    }

    override func layout() {
        super.layout()
        controller.renderer.rootLayer.frame = bounds
        controller.resize(to: bounds.size, insets: insets)
        if window != nil { startFrames() }
    }

    func load(ranked: [MidgarApp], hostBundleID: String?, installed: Set<String>, initialFocus: String?) {
        apps = Dictionary(uniqueKeysWithValues: ranked.map { ($0.appId, $0) })
        controller.load(ranked: ranked, hostBundleID: hostBundleID, installed: installed, initialFocus: initialFocus)
        controller.resize(to: bounds.size, insets: insets)
        loadArtwork(for: ranked)
        if window != nil {
            controller.begin()
            didBegin = true
        }
    }

    func setInstalled(_ bundleIDs: Set<String>) {
        controller.setInstalled(bundleIDs)
    }

    func focus(appID: String) {
        controller.bringToCentre(appID: appID)
    }

    private func wireController() {
        controller.onNeedsFrames = { [weak self] needed in
            needed ? self?.startFrames() : self?.stopFrames()
        }
    }

    private func topLeft(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = topLeft(event)
        dragSamples = [(event.timestamp, dragOrigin)]
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = topLeft(event)
        if !didDrag, hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) < 4 { return }
        if !didDrag {
            didDrag = true
            controller.pointerBegan()
        }
        dragSamples.append((event.timestamp, point))
        dragSamples = dragSamples.filter { event.timestamp - $0.time < 0.1 }
        controller.pointerMoved(translation: CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard didDrag else {
            controller.tap(at: topLeft(event))
            return
        }
        controller.pointerEnded(velocity: velocity(endingAt: topLeft(event), time: event.timestamp))
    }

    private func velocity(endingAt point: CGPoint, time: TimeInterval) -> CGPoint {
        guard let first = dragSamples.first, time - first.time > 0.001 else { return .zero }
        let span = CGFloat(time - first.time)
        return CGPoint(x: (point.x - first.point.x) / span, y: (point.y - first.point.y) / span)
    }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        let unit: CGFloat = precise ? 1 : 12
        let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        controller.scrolled(by: CGPoint(
            x: event.scrollingDeltaX * unit * direction,
            y: event.scrollingDeltaY * unit * direction
        ))
        scrollIdle?.invalidate()
        let finished = event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended
        if finished || !precise {
            let delay: TimeInterval = finished ? 0.02 : 0.14
            scrollIdle = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.scrollEnded() }
            }
        } else {
            scrollIdle = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.scrollEnded() }
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: controller.moveFocus(toward: CGVector(dx: -1, dy: 0))
        case 124: controller.moveFocus(toward: CGVector(dx: 1, dy: 0))
        case 125: controller.moveFocus(toward: CGVector(dx: 0, dy: 1))
        case 126: controller.moveFocus(toward: CGVector(dx: 0, dy: -1))
        case 36, 49, 76: controller.activateFocused()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    private func startFrames() {
        guard displayLink == nil, fallbackTimer == nil, window != nil else { return }
        if #available(macOS 14.0, *) {
            let link = displayLink(target: self, selector: #selector(frame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.tick(now: CACurrentMediaTime()) }
            }
        }
    }

    private func stopFrames() {
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    @available(macOS 14.0, *)
    @objc private func frame(_ link: CADisplayLink) {
        controller.tick(now: link.timestamp)
    }

    private func loadArtwork(for ranked: [MidgarApp]) {
        let pixels = max(controller.renderer.baseDiameter, 120)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for app in ranked {
            Task { @MainActor [weak self] in
                if let fallback = await midgarBundledCGImage(app.appId, maxPixel: pixels, scale: scale) {
                    self?.controller.setArtwork(fallback, forApp: app.appId)
                }
                if let remote = await midgarLoadCGImage(app.iconURL, maxPixel: pixels, scale: scale) {
                    self?.controller.setArtwork(remote, forApp: app.appId)
                }
            }
        }
    }

    override func isAccessibilityElement() -> Bool { false }

    override func accessibilityChildren() -> [Any]? {
        controller.layout.cells.map { cell in
            let element = NSAccessibilityElement()
            let app = cell.appID.flatMap { apps[$0] }
            element.setAccessibilityLabel(app?.name ?? "Midgar")
            element.setAccessibilityHelp(app?.tagline ?? MidgarStrings.coreAccessibilityHint)
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            if let frame = controller.frame(forCell: cell.index) {
                let rect = NSRect(
                    x: frame.center.x - frame.radius,
                    y: bounds.height - frame.center.y - frame.radius,
                    width: frame.radius * 2, height: frame.radius * 2
                )
                element.setAccessibilityFrameInParentSpace(rect)
            }
            return element
        }
    }
}
#endif
