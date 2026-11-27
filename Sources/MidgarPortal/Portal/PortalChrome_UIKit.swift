#if canImport(UIKit)
import UIKit

extension PortalColor {
    var uiColor: UIColor { UIColor(cgColor: cgColor) }
}

/// The portal's type: SF Pro Rounded at fixed sizes that read the same in every app that hosts it.
enum PortalFont {
    static func rounded(_ size: CGFloat, _ weight: UIFont.Weight, monospacedDigits: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size * PortalMetrics.scale, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        if monospacedDigits {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }
}

/// Liquid Glass where the system has it, a dark frosted material with a hairline edge before.
/// `cornerRadius` of `nil` makes a capsule.
@MainActor
final class PortalGlassView: UIView {
    let contentView = UIView()
    private let effectView: UIVisualEffectView
    private let cornerRadius: CGFloat?

    init(cornerRadius: CGFloat?) {
        self.cornerRadius = cornerRadius
        effectView = UIVisualEffectView(effect: Self.makeEffect())
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        effectView.isUserInteractionEnabled = false
        addSubview(effectView)
        addSubview(contentView)
        if Self.hasLiquidGlass {
            applyGlassCorners()
        } else {
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
            effectView.layer.borderWidth = 1
            effectView.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.frame = bounds
        contentView.frame = bounds
        if !Self.hasLiquidGlass {
            effectView.layer.cornerRadius = cornerRadius ?? bounds.height / 2
        }
    }

    static var hasLiquidGlass: Bool {
        #if os(visionOS)
        return false
        #else
        if #available(iOS 26.0, tvOS 26.0, *) { return true }
        return false
        #endif
    }

    private static func makeEffect() -> UIVisualEffect {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, *) { return UIGlassEffect() }
        #endif
        #if os(tvOS)
        return UIBlurEffect(style: .dark)
        #else
        return UIBlurEffect(style: .systemUltraThinMaterialDark)
        #endif
    }

    private func applyGlassCorners() {
        #if !os(visionOS)
        if #available(iOS 26.0, tvOS 26.0, *) {
            effectView.cornerConfiguration = cornerRadius.map { .uniformCorners(radius: UICornerRadius(floatLiteral: Double($0))) } ?? .capsule()
        }
        #endif
    }
}

/// A short label on a tinted capsule: "Installed", a genre, a purchase name.
@MainActor
final class PortalChipView: UIView {
    private let label = UILabel()
    private static let padding = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = PortalFont.rounded(11, .semibold)
        label.textColor = UIColor(white: 1, alpha: 0.9)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        layer.cornerCurve = .continuous
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var accent: PortalColor?

    /// Changes only what differs, so moving between two apps of one genre redraws nothing.
    func configure(text: String, accent: PortalColor?) {
        if label.text != text {
            label.text = text
            setNeedsLayout()
        }
        guard accent != self.accent || backgroundColor == nil else { return }
        self.accent = accent
        backgroundColor = accent.map { $0.withAlpha(0.42).uiColor } ?? UIColor(white: 1, alpha: 0.12)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
        return CGSize(
            width: ceil(text.width) + Self.padding.left + Self.padding.right,
            height: ceil(text.height) + Self.padding.top + Self.padding.bottom
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        label.frame = bounds.inset(by: Self.padding)
    }
}

/// The card's call to action: a lit capsule in the app's colour.
@MainActor
final class PortalPillControl: UIControl {
    private let label = UILabel()
    private let fill = CAGradientLayer()
    private var accent = PortalColor.midgar
    static let height: CGFloat = 38 * PortalMetrics.scale

    override init(frame: CGRect) {
        super.init(frame: frame)
        fill.borderWidth = 1
        fill.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
        fill.masksToBounds = true
        layer.addSublayer(fill)
        layer.shadowOpacity = 1
        layer.shadowRadius = 7
        layer.shadowOffset = CGSize(width: 0, height: 3)
        label.font = PortalFont.rounded(15, .heavy)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        #if os(tvOS)
        isUserInteractionEnabled = false
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    #if os(tvOS)
    override var canBecomeFocused: Bool { false }
    #endif

    /// Changes only what differs: most apps share the same "GET", so the label is rarely redrawn.
    func configure(title: String, accent: PortalColor) {
        if label.text != title {
            label.text = title
            accessibilityLabel = title
            setNeedsLayout()
        }
        guard accent != self.accent || fill.colors == nil else { return }
        self.accent = accent
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.colors = [accent.lightened(0.18).cgColor, accent.darkened(0.2).cgColor]
        layer.shadowColor = accent.withAlpha(0.5).cgColor
        CATransaction.commit()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: Self.height))
        return CGSize(width: ceil(text.width) + 44 * PortalMetrics.scale, height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        fill.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        CATransaction.commit()
        label.frame = bounds.insetBy(dx: 16 * PortalMetrics.scale, dy: 0)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            }
        }
    }
}

/// The slim bar over the canvas: the Midgar name with how many of the apps the person has, and on
/// touch screens the "Your Midgar" and close buttons.
@MainActor
final class PortalHeaderView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textGroup = UIView()
    let yourMidgarButton = UIButton(type: .system)
    let closeButton = UIButton(type: .system)
    private static let inset: CGFloat = 20
    private static let buttonSide: CGFloat = 36 * PortalMetrics.scale

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = "Midgar"
        titleLabel.font = PortalFont.rounded(20, .bold)
        titleLabel.textColor = .white
        subtitleLabel.font = PortalFont.rounded(12, .medium, monospacedDigits: true)
        subtitleLabel.textColor = UIColor(white: 1, alpha: 0.62)
        textGroup.addSubview(titleLabel)
        textGroup.addSubview(subtitleLabel)
        textGroup.isAccessibilityElement = true
        addSubview(textGroup)
        #if !os(tvOS)
        configureButtons()
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var subtitle: String? {
        get { subtitleLabel.text }
        set {
            guard newValue != subtitleLabel.text else { return }
            subtitleLabel.text = newValue
            textGroup.accessibilityLabel = ["Midgar", newValue].compactMap { $0 }.joined(separator: ", ")
            setNeedsLayout()
        }
    }

    var showsYourMidgar = false {
        didSet {
            guard showsYourMidgar != oldValue else { return }
            yourMidgarButton.isHidden = !showsYourMidgar
            setNeedsLayout()
        }
    }

    #if !os(tvOS)
    private func configureButtons() {
        var capsule = Self.buttonConfiguration(capsule: true)
        capsule.attributedTitle = AttributedString(
            MidgarStrings.yourMidgar,
            attributes: AttributeContainer([.font: PortalFont.rounded(13, .semibold), .foregroundColor: UIColor.white])
        )
        capsule.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        yourMidgarButton.configuration = capsule
        yourMidgarButton.isHidden = true

        var circle = Self.buttonConfiguration(capsule: false)
        circle.image = UIImage(systemName: "xmark")
        circle.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14 * PortalMetrics.scale, weight: .bold)
        circle.baseForegroundColor = .white
        circle.contentInsets = .zero
        closeButton.configuration = circle
        closeButton.accessibilityLabel = MidgarStrings.close
        addSubview(yourMidgarButton)
        addSubview(closeButton)
    }

    /// Glass buttons from iOS 26, a frosted capsule with a hairline edge before.
    private static func buttonConfiguration(capsule: Bool) -> UIButton.Configuration {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            var glass = UIButton.Configuration.glass()
            glass.cornerStyle = .capsule
            glass.baseForegroundColor = .white
            return glass
        }
        #endif
        var plain = UIButton.Configuration.plain()
        plain.cornerStyle = .capsule
        plain.baseForegroundColor = .white
        var background = UIBackgroundConfiguration.clear()
        background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        background.strokeColor = UIColor(white: 1, alpha: 0.18)
        background.strokeWidth = 1
        plain.background = background
        return plain
    }
    #endif

    override func layoutSubviews() {
        super.layoutSubviews()
        var trailing = bounds.width - Self.inset
        let side = Self.buttonSide
        let buttonY = (bounds.height - side) / 2
        if !closeButton.isHidden, closeButton.superview != nil {
            closeButton.frame = CGRect(x: trailing - side, y: buttonY, width: side, height: side)
            trailing -= side + 12
        }
        if !yourMidgarButton.isHidden, yourMidgarButton.superview != nil {
            let width = ceil(yourMidgarButton.sizeThatFits(CGSize(width: 240, height: side)).width)
            yourMidgarButton.frame = CGRect(x: trailing - width, y: buttonY, width: width, height: side)
            trailing -= width + 12
        }
        let textWidth = max(0, trailing - Self.inset)
        let fit = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        let titleHeight = ceil(titleLabel.sizeThatFits(fit).height)
        let subtitleHeight = ceil(subtitleLabel.sizeThatFits(fit).height)
        let total = titleHeight + 2 + subtitleHeight
        textGroup.frame = CGRect(x: Self.inset, y: (bounds.height - total) / 2, width: textWidth, height: total)
        titleLabel.frame = CGRect(x: 0, y: 0, width: textWidth, height: titleHeight)
        subtitleLabel.frame = CGRect(x: 0, y: titleHeight + 2, width: textWidth, height: subtitleHeight)
    }
}

/// What the bottom card shows, worked out from the model so the card itself only lays it out.
struct PortalCardContent: Equatable {
    struct Chip: Equatable {
        let text: String
        let accent: PortalColor?
    }

    struct Button: Equatable {
        let title: String
        let accent: PortalColor
    }

    let title: String
    let body: String
    let bodyLines: Int
    let rating: String?
    let chips: [Chip]
    let button: Button?
}

/// The glass card describing whatever sits at the centre of the canvas.
@MainActor
final class PortalCardView: UIView {
    private let glass = PortalGlassView(cornerRadius: 30)
    private let content = UIView()
    private let titleLabel = UILabel()
    private let ratingLabel = UILabel()
    private let ratingStar = UIImageView()
    private let bodyLabel = UILabel()
    private let chipViews = [PortalChipView(), PortalChipView()]
    let button = PortalPillControl()
    private(set) var current: PortalCardContent?
    private static let padding: CGFloat = 18 * PortalMetrics.scale
    private static let gold = UIColor(red: 1, green: 0.8, blue: 0.25, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glass)
        glass.contentView.addSubview(content)
        titleLabel.font = PortalFont.rounded(22, .bold)
        titleLabel.textColor = .white
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        titleLabel.accessibilityTraits = .header
        ratingLabel.font = PortalFont.rounded(13, .semibold, monospacedDigits: true)
        ratingLabel.textColor = Self.gold
        ratingStar.image = UIImage(systemName: "star.fill")
        ratingStar.tintColor = Self.gold
        ratingStar.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: PortalFont.rounded(11, .semibold))
        ratingStar.contentMode = .scaleAspectFit
        bodyLabel.font = PortalFont.rounded(15, .regular)
        bodyLabel.lineBreakMode = .byTruncatingTail
        for view in [titleLabel, ratingStar, ratingLabel, bodyLabel] { content.addSubview(view) }
        for chip in chipViews { content.addSubview(chip) }
        content.addSubview(button)
        ratingStar.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `next`, fading the new words in the way the card always has when the focus moves.
    func show(_ next: PortalCardContent, animated: Bool) {
        guard next != current else { return }
        let previous = current
        current = next
        if next.title != previous?.title { titleLabel.text = next.title }
        if next.body != previous?.body || next.bodyLines != previous?.bodyLines {
            bodyLabel.text = next.body
            bodyLabel.numberOfLines = next.bodyLines
            bodyLabel.textColor = UIColor(white: 1, alpha: next.bodyLines == 2 ? 0.72 : 0.7)
        }
        if next.rating != previous?.rating { ratingLabel.text = next.rating }
        ratingLabel.isHidden = next.rating == nil
        ratingStar.isHidden = next.rating == nil
        for (index, chip) in chipViews.enumerated() {
            if index < next.chips.count {
                chip.configure(text: next.chips[index].text, accent: next.chips[index].accent)
                chip.isHidden = false
            } else {
                chip.isHidden = true
            }
        }
        if let action = next.button {
            button.configure(title: action.title, accent: action.accent)
            button.isHidden = false
        } else {
            button.isHidden = true
        }
        setNeedsLayout()
        guard animated else {
            content.layer.removeAllAnimations()
            content.alpha = 1
            return
        }
        content.alpha = 0
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
            self.content.alpha = 1
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        content.frame = bounds
        let padding = Self.padding
        let width = bounds.width - padding * 2
        let bottom = bounds.height - padding

        var buttonWidth: CGFloat = 0
        if !button.isHidden {
            let size = button.sizeThatFits(.zero)
            buttonWidth = min(size.width, width * 0.6)
            button.frame = CGRect(x: bounds.width - padding - buttonWidth, y: bottom - size.height, width: buttonWidth, height: size.height)
        }

        var ratingWidth: CGFloat = 0
        let titleHeight = ceil(titleLabel.font.lineHeight)
        if !ratingLabel.isHidden {
            let text = ratingLabel.sizeThatFits(CGSize(width: 80, height: titleHeight))
            let star = ratingStar.sizeThatFits(CGSize(width: 20, height: 20))
            ratingWidth = ceil(text.width) + star.width + 4
            let baseline = padding + titleLabel.font.ascender
            let textY = baseline - ratingLabel.font.ascender
            ratingLabel.frame = CGRect(x: bounds.width - padding - ceil(text.width), y: textY, width: ceil(text.width), height: ceil(text.height))
            ratingStar.frame = CGRect(
                x: ratingLabel.frame.minX - 4 - star.width,
                y: ratingLabel.frame.midY - star.height / 2,
                width: star.width,
                height: star.height
            )
        }
        titleLabel.frame = CGRect(x: padding, y: padding, width: max(0, width - (ratingWidth > 0 ? ratingWidth + 8 : 0)), height: titleHeight)

        let runsLong = current?.bodyLines == 0
        let bodyTop = titleLabel.frame.maxY + (runsLong ? 10 : 8)
        let rowTop = button.isHidden ? bottom - PortalPillControl.height : button.frame.minY
        let bodyLimit = max(0, rowTop - (runsLong ? 6 : 4) - bodyTop)
        let bodyFit = bodyLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        bodyLabel.frame = CGRect(x: padding, y: bodyTop, width: width, height: min(ceil(bodyFit.height), bodyLimit))

        var chipX = padding
        let chipLimit = bounds.width - padding - (buttonWidth > 0 ? buttonWidth + 8 : 0)
        let rowMid = button.isHidden ? bottom - PortalPillControl.height / 2 : button.frame.midY
        for chip in chipViews where !chip.isHidden {
            let size = chip.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 30))
            let chipWidth = min(size.width, max(0, chipLimit - chipX))
            chip.frame = CGRect(x: chipX, y: rowMid - size.height / 2, width: chipWidth, height: size.height)
            chip.isHidden = chipWidth < 24
            chipX += chipWidth + 8
        }
    }
}

/// Deep space behind the canvas, lit by the focused app's colour, which crossfades as the focus
/// moves. Three gradient layers, nothing redrawn per frame.
@MainActor
final class PortalBackdropView: UIView {
    private let base = CAGradientLayer()
    private let accentGlow = CAGradientLayer()
    private let cornerGlow = CAGradientLayer()
    private var accent: PortalColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        base.colors = [PortalColor.space.cgColor, PortalColor(r: 0.045, g: 0.05, b: 0.15).cgColor]
        base.startPoint = CGPoint(x: 0.5, y: 0)
        base.endPoint = CGPoint(x: 0.5, y: 1)
        accentGlow.type = .radial
        accentGlow.locations = [0, 0.5, 1]
        cornerGlow.type = .radial
        cornerGlow.colors = [PortalColor.midgar.withAlpha(0.14).cgColor, PortalColor.midgar.withAlpha(0).cgColor]
        for layer in [base, accentGlow, cornerGlow] { self.layer.addSublayer(layer) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setAccent(_ color: PortalColor, animated: Bool) {
        guard color != accent else { return }
        accent = color
        let colors = [color.withAlpha(0.42).cgColor, color.withAlpha(0.12).cgColor, color.withAlpha(0).cgColor]
        let from = accentGlow.presentation()?.colors ?? accentGlow.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        accentGlow.colors = colors
        CATransaction.commit()
        guard animated, from != nil else { return }
        let fade = CABasicAnimation(keyPath: "colors")
        fade.fromValue = from
        fade.toValue = colors
        fade.duration = 0.7
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        accentGlow.add(fade, forKey: "accent")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [base, accentGlow, cornerGlow] { layer.frame = bounds }
        Self.place(accentGlow, centre: CGPoint(x: 0.5, y: 0.42), radius: 460, in: bounds.size)
        Self.place(cornerGlow, centre: CGPoint(x: 0.95, y: 0.02), radius: 360, in: bounds.size)
        CATransaction.commit()
    }

    /// A radial gradient layer reaches from `startPoint` to `endPoint` in unit coordinates, so a
    /// circle of `radius` points needs its end point scaled by each side separately.
    private static func place(_ layer: CAGradientLayer, centre: CGPoint, radius: CGFloat, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        layer.startPoint = centre
        layer.endPoint = CGPoint(x: centre.x + radius / size.width, y: centre.y + radius / size.height)
    }
}
#endif
