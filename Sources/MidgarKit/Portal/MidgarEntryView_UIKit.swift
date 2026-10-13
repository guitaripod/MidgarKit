#if canImport(UIKit)
import UIKit

/// The doorway into the portal: a card that shows a live miniature of the honeycomb, with the
/// host's closest relatives nearest the middle. Drop it into a settings screen; tapping it opens
/// the portal with an iris that grows out of the card.
@MainActor
public final class MidgarEntryView: UIControl {
    public static let preferredHeight: CGFloat = 116

    private let config: MidgarConfig
    private let renderer: PortalRenderer
    private let backdrop = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let clip = CALayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var ranked: [MidgarApp] = []
    private var loadedIDs: [String] = []

    public init(config: MidgarConfig = MidgarConfig(placement: "entry")) {
        self.config = config
        let scale = MidgarEntryView.displayScale()
        renderer = PortalRenderer(
            layout: PortalLayout.make(appIDs: [], pitch: 46),
            scale: scale,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        super.init(frame: CGRect(x: 0, y: 0, width: 360, height: Self.preferredHeight))
        configureLayers()
        configureLabels()
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Midgar"
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        reload()
        PortalEntryContent.refreshIfStale(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func displayScale() -> CGFloat {
        #if os(visionOS)
        return 2
        #else
        return UIScreen.main.scale
        #endif
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.preferredHeight)
    }

    /// Pins the card inside `container` (a cell's content view, a stack, a header) with the given
    /// vertical padding, so every host places it the same way.
    public func embed(in container: UIView, verticalInset: CGFloat = 8, horizontalInset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: container.topAnchor, constant: verticalInset),
            bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalInset),
            leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
        ])
    }

    #if os(tvOS)
    public override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.transform = self.isFocused ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            self.layer.shadowOpacity = self.isFocused ? 0.5 : 0.28
        }
    }
    #endif

    public override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.975, y: 0.975) : .identity
                self.alpha = self.isHighlighted ? 0.92 : 1
            }
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        clip.frame = bounds
        clip.cornerRadius = 26
        backdrop.frame = bounds
        glow.frame = bounds
        renderer.rootLayer.frame = bounds
        let center = CGPoint(x: max(bounds.width - 80, bounds.width * 0.64), y: bounds.height / 2)
        renderer.setViewport(
            size: bounds.size,
            center: center,
            halfExtent: CGSize(width: 108, height: 78),
            diameter: 38
        )
        renderer.render(camera: .zero, intro: 99)
        let textWidth = max(0, center.x - 66 - 20)
        titleLabel.frame = CGRect(x: 20, y: bounds.height / 2 - 34, width: textWidth, height: 26)
        subtitleLabel.frame = CGRect(x: 20, y: bounds.height / 2 + 0, width: textWidth, height: 36)
        chevron.frame = CGRect(x: 20, y: bounds.height - 34, width: 14, height: 16)
    }

    private func configureLayers() {
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
        clip.masksToBounds = true
        clip.cornerCurve = .continuous
        clip.borderWidth = 1
        clip.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        backdrop.colors = [
            PortalColor(r: 0.03, g: 0.035, b: 0.1).cgColor,
            PortalColor(r: 0.09, g: 0.1, b: 0.3).cgColor,
        ]
        backdrop.startPoint = CGPoint(x: 0, y: 0)
        backdrop.endPoint = CGPoint(x: 1, y: 1)
        glow.type = .radial
        glow.colors = [PortalColor.midgar.withAlpha(0.45).cgColor, PortalColor.midgar.withAlpha(0).cgColor]
        glow.startPoint = CGPoint(x: 0.78, y: 0.5)
        glow.endPoint = CGPoint(x: 1.25, y: 1.1)
        layer.addSublayer(clip)
        clip.addSublayer(backdrop)
        clip.addSublayer(glow)
        clip.addSublayer(renderer.rootLayer)
    }

    private func configureLabels() {
        titleLabel.text = MidgarStrings.entryTitle
        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 18, weight: .bold).rounded)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .medium).rounded)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.7)
        subtitleLabel.numberOfLines = 2
        chevron.tintColor = UIColor(white: 1, alpha: 0.85)
        chevron.contentMode = .scaleAspectFit
        for view in [titleLabel, subtitleLabel, chevron] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
    }

    private func reload() {
        let host = Bundle.main.bundleIdentifier
        ranked = PortalEntryContent.ranked(hostBundleID: host, installed: [])
        subtitleLabel.text = PortalEntryContent.subtitle(appCount: ranked.count)
        accessibilityValue = subtitleLabel.text
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
        setNeedsLayout()
        loadArtwork(for: shown)
    }

    private func loadArtwork(for apps: [MidgarApp]) {
        let scale = Self.displayScale()
        for app in apps {
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

    @objc private func tapped() {
        Midgar.present(from: nearestViewController(), config: portalConfig, sourceView: self)
    }

    private var portalConfig: MidgarConfig {
        var copy = config
        copy.placement = "entry"
        return copy
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
