import MidgarUI
#if canImport(AppKit) && !canImport(UIKit)

/// The doorway into the portal on macOS: a card with a live miniature of the honeycomb. Click it
/// to open the portal as a sheet.
@MainActor
public final class MidgarEntryView: NSControl {
    public static let preferredHeight: CGFloat = 116

    private let config: MidgarConfig
    private let renderer: PortalRenderer
    private let backdrop = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let clip = CALayer()
    private let titleLabel = NSTextField(labelWithString: MidgarStrings.entryTitle)
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var loadedIDs: [String] = []
    private var pressed = false

    public init(config: MidgarConfig = MidgarConfig(placement: "entry")) {
        self.config = config
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer = PortalRenderer(
            layout: PortalLayout.make(appIDs: [], pitch: 46),
            scale: scale,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: Self.preferredHeight))
        wantsLayer = true
        configureLayers()
        configureLabels()
        setAccessibilityRole(.button)
        setAccessibilityLabel("Midgar")
        reload()
        PortalEntryContent.refreshIfStale(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    public override func layout() {
        super.layout()
        clip.frame = bounds
        backdrop.frame = bounds
        glow.frame = bounds
        renderer.rootLayer.frame = bounds
        let center = CGPoint(x: max(bounds.width - 80, bounds.width * 0.64), y: bounds.height / 2)
        renderer.setViewport(size: bounds.size, center: center, halfExtent: CGSize(width: 108, height: 78), diameter: 38)
        renderer.render(camera: .zero, intro: 99)
        layoutLabels(textWidth: max(0, center.x - 66 * PortalMetrics.scale - 20 * PortalMetrics.scale))
    }

    /// Stacks the title and subtitle as one block, centred vertically in the card.
    private func layoutLabels(textWidth: CGFloat) {
        let titleHeight = titleLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let subtitleHeight = min(subtitleLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height, bounds.height * 0.4)
        let gap: CGFloat = 3
        let total = titleHeight + gap + subtitleHeight
        let bottom = (bounds.height - total) / 2
        subtitleLabel.frame = NSRect(x: 20, y: bottom, width: textWidth, height: subtitleHeight)
        titleLabel.frame = NSRect(x: 20, y: bottom + subtitleHeight + gap, width: textWidth, height: titleHeight)
    }

    public override func mouseDown(with event: NSEvent) {
        pressed = true
        alphaValue = 0.9
    }

    public override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        defer { pressed = false }
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        Midgar.present(config: config)
    }

    private func configureLayers() {
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        clip.masksToBounds = true
        clip.cornerRadius = 26
        clip.cornerCurve = .continuous
        clip.borderWidth = 1
        clip.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        backdrop.colors = [
            PortalColor(r: 0.03, g: 0.035, b: 0.1).cgColor,
            PortalColor(r: 0.09, g: 0.1, b: 0.3).cgColor,
        ]
        backdrop.startPoint = CGPoint(x: 0, y: 1)
        backdrop.endPoint = CGPoint(x: 1, y: 0)
        glow.type = .radial
        glow.colors = [PortalColor.midgar.withAlpha(0.45).cgColor, PortalColor.midgar.withAlpha(0).cgColor]
        glow.startPoint = CGPoint(x: 0.78, y: 0.5)
        glow.endPoint = CGPoint(x: 1.25, y: 1.1)
        layer?.addSublayer(clip)
        clip.addSublayer(backdrop)
        clip.addSublayer(glow)
        clip.addSublayer(renderer.rootLayer)
    }

    private func configureLabels() {
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .white
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = NSColor(white: 1, alpha: 0.7)
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }

    private func reload() {
        let host = Bundle.main.bundleIdentifier
        let ranked = PortalEntryContent.ranked(hostBundleID: host, installed: [])
        subtitleLabel.stringValue = PortalEntryContent.subtitle(appCount: ranked.count)
        setAccessibilityValue(subtitleLabel.stringValue)
        let ids = ranked.map(\.appId)
        guard ids != loadedIDs else { return }
        loadedIDs = ids
        let shown = Array(ranked.filter { $0.bundleId.lowercased() != host?.lowercased() }.prefix(12))
        let layout = PortalLayout.make(appIDs: shown.map(\.appId), pitch: 46, ghostRings: 1)
        renderer.configure(
            layout: layout,
            apps: Dictionary(uniqueKeysWithValues: shown.map { ($0.appId, $0) }),
            hostBundleID: host,
            installed: []
        )
        needsLayout = true
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for app in shown {
            Task { @MainActor [weak self] in
                if let fallback = await midgarBundledCGImage(app.appId, maxPixel: 96, scale: scale) {
                    self?.renderer.setArtwork(fallback, forApp: app.appId)
                }
                if let remote = await midgarLoadCGImage(app.iconURL, maxPixel: 96, scale: scale) {
                    self?.renderer.setArtwork(remote, forApp: app.appId)
                }
            }
        }
    }
}
#endif
