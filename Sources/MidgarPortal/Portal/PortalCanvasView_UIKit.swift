#if canImport(UIKit)
import UIKit

/// The portal canvas on iOS, iPadOS, tvOS and visionOS: a plain view that hosts the renderer's
/// layers, turns touches into camera motion and runs a display link only while something moves.
@MainActor
final class PortalCanvasView: UIView {
    let controller: PortalController
    var insets = PortalInsets() {
        didSet { if insets != oldValue { setNeedsLayout() } }
    }

    private var displayLink: CADisplayLink?
    private var panStart: CGPoint = .zero
    private var didBegin = false
    private var accessibilityCells: [UIAccessibilityElement] = []
    private var apps: [String: MidgarApp] = [:]
    var onAccessibilityActivate: ((PortalCell) -> Void)?

    #if os(iOS)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    #endif

    override init(frame: CGRect) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        controller = PortalController(scale: PortalCanvasView.screenScale(), reduceMotion: reduce)
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(controller.renderer.rootLayer)
        isAccessibilityElement = false
        installGestures()
        wireController()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func screenScale() -> CGFloat {
        #if os(visionOS)
        return 2
        #else
        return UIScreen.main.scale
        #endif
    }

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            stopDisplayLink()
            return
        }
        layoutIfNeeded()
        if !didBegin {
            didBegin = true
            controller.begin()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        controller.renderer.rootLayer.frame = bounds
        controller.resize(to: bounds.size, insets: insets)
        if window != nil { startDisplayLink() }
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
        rebuildAccessibility()
    }

    func setInstalled(_ bundleIDs: Set<String>) {
        controller.setInstalled(bundleIDs)
    }

    func focus(appID: String) {
        controller.bringToCentre(appID: appID)
    }

    private func wireController() {
        controller.onNeedsFrames = { [weak self] needed in
            needed ? self?.startDisplayLink() : self?.stopDisplayLink()
        }
        controller.onHaptic = { [weak self] in
            #if os(iOS)
            self?.selectionFeedback.selectionChanged()
            self?.selectionFeedback.prepare()
            #endif
        }
        controller.onFramesSettled = { [weak self] in
            self?.rebuildAccessibility()
        }
    }

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        #if os(tvOS)
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        #else
        pan.maximumNumberOfTouches = 1
        #endif
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        #if os(tvOS)
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        #endif
        addGestureRecognizer(tap)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            #if os(iOS)
            selectionFeedback.prepare()
            #endif
            controller.pointerBegan()
        case .changed:
            controller.pointerMoved(translation: gesture.translation(in: self))
        case .ended:
            controller.pointerEnded(velocity: gesture.velocity(in: self))
        case .cancelled, .failed:
            controller.pointerEnded(velocity: .zero)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        #if os(tvOS)
        controller.activateFocused()
        #else
        controller.tap(at: gesture.location(in: self))
        #endif
    }

    #if os(tvOS)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.type {
            case .leftArrow: controller.moveFocus(toward: CGVector(dx: -1, dy: 0)); handled = true
            case .rightArrow: controller.moveFocus(toward: CGVector(dx: 1, dy: 0)); handled = true
            case .upArrow: controller.moveFocus(toward: CGVector(dx: 0, dy: -1)); handled = true
            case .downArrow: controller.moveFocus(toward: CGVector(dx: 0, dy: 1)); handled = true
            default: break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
    #endif

    @objc private func reduceMotionChanged() {
        controller.setReduceMotion(UIAccessibility.isReduceMotionEnabled)
    }

    private func startDisplayLink() {
        guard displayLink == nil, window != nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func frame(_ link: CADisplayLink) {
        controller.tick(now: link.timestamp)
    }

    private func loadArtwork(for ranked: [MidgarApp]) {
        let pixels = max(controller.renderer.baseDiameter, 120)
        let scale = traitCollection.displayScale
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

    private func rebuildAccessibility() {
        accessibilityCells = controller.layout.cells.map { cell in
            let element = PortalAccessibilityElement(accessibilityContainer: self)
            element.cell = cell
            let app = cell.appID.flatMap { apps[$0] }
            element.accessibilityLabel = app?.name ?? "Midgar"
            element.accessibilityHint = app?.tagline ?? MidgarStrings.coreAccessibilityHint
            element.accessibilityTraits = .button
            if let frame = controller.frame(forCell: cell.index) {
                let rect = CGRect(
                    x: frame.center.x - frame.radius, y: frame.center.y - frame.radius,
                    width: frame.radius * 2, height: frame.radius * 2
                )
                element.accessibilityFrameInContainerSpace = rect
            }
            element.onActivate = { [weak self] cell in self?.onAccessibilityActivate?(cell) }
            element.onFocus = { [weak self] cell in self?.controller.bringToCentre(cell) }
            return element
        }
        accessibilityElements = accessibilityCells
    }
}

private final class PortalAccessibilityElement: UIAccessibilityElement {
    var cell: PortalCell?
    var onActivate: ((PortalCell) -> Void)?
    var onFocus: ((PortalCell) -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let cell else { return false }
        onActivate?(cell)
        return true
    }

    override func accessibilityElementDidBecomeFocused() {
        guard let cell else { return }
        onFocus?(cell)
    }
}

private final class DisplayLinkProxy {
    weak var target: PortalCanvasView?

    init(_ target: PortalCanvasView) { self.target = target }

    @MainActor @objc func fire(_ link: CADisplayLink) {
        target?.frame(link)
    }
}
#endif
