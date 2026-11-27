#if canImport(UIKit) && !os(tvOS)
import UIKit

/// The "Your Midgar" panel: the Midgar apps the person has with what they own in each, then a few
/// more worth a look. It sits over the canvas, between the header and the bottom card, and scrolls
/// when it is taller than the room it is given.
@MainActor
final class YourMidgarPanelView: UIView {
    var onSelect: ((MidgarApp) -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var shown: (section: YourMidgarSection, host: String?, installed: Set<String>)?
    private static let inset: CGFloat = 18 * PortalMetrics.scale
    private static let headerHeight: CGFloat = (16 + 30 + 10) * PortalMetrics.scale

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = YourMidgarSurface.panel.uiColor
        layer.cornerRadius = 30
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        clipsToBounds = true
        configureHeader()
        configureList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(section: YourMidgarSection, hostBundleID: String?, installed: Set<String>) {
        let host = hostBundleID?.lowercased()
        if let shown, shown.section == section, shown.host == host, shown.installed == installed { return }
        shown = (section, host, installed)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(group(
            title: MidgarStrings.yourApps,
            rows: section.yours.map { yours in
                YourMidgarRowView(app: yours.app, owned: yours.owned, status: status(for: yours.app, host: host, installed: installed), priceLabel: nil)
            }
        ))
        if !section.suggestions.isEmpty {
            stack.addArrangedSubview(group(
                title: MidgarStrings.moreFromMidgar,
                rows: section.suggestions.map { YourMidgarRowView(app: $0, owned: [], status: nil, priceLabel: $0.priceLabel) }
            ))
        }
        setNeedsLayout()
    }

    /// The height the panel needs at `width` to show every row without scrolling.
    func naturalHeight(forWidth width: CGFloat) -> CGFloat {
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: max(0, width - Self.inset * 2), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return Self.headerHeight + ceil(fitting.height) + Self.inset
    }

    private func configureHeader() {
        titleLabel.text = MidgarStrings.yourMidgar
        titleLabel.font = PortalFont.rounded(22, .bold)
        titleLabel.textColor = .white
        titleLabel.accessibilityTraits = .header
        var close = UIButton.Configuration.plain()
        close.image = UIImage(systemName: "chevron.down")
        close.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12 * PortalMetrics.scale, weight: .bold)
        close.baseForegroundColor = .white
        close.cornerStyle = .capsule
        close.contentInsets = .zero
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = UIColor(white: 1, alpha: 0.14)
        close.background = background
        closeButton.configuration = close
        closeButton.accessibilityLabel = MidgarStrings.close
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .primaryActionTriggered)
        addSubview(titleLabel)
        addSubview(closeButton)
    }

    private func configureList() {
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.indicatorStyle = .white
        scrollView.alwaysBounceVertical = false
        scrollView.addSubview(stack)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Self.inset),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -Self.inset),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = 30 * PortalMetrics.scale
        let top = 16 * PortalMetrics.scale
        closeButton.frame = CGRect(x: bounds.width - Self.inset - side, y: top, width: side, height: side)
        titleLabel.frame = CGRect(x: Self.inset, y: top, width: max(0, closeButton.frame.minX - 8 - Self.inset), height: side)
        scrollView.frame = CGRect(x: 0, y: Self.headerHeight, width: bounds.width, height: max(0, bounds.height - Self.headerHeight))
    }

    private func group(title: String, rows: [YourMidgarRowView]) -> UIView {
        let heading = UILabel()
        heading.text = title.uppercased()
        heading.font = PortalFont.rounded(12, .semibold)
        heading.textColor = UIColor(white: 1, alpha: 0.55)
        heading.accessibilityTraits = .header
        let column = UIStackView(arrangedSubviews: [heading] + rows)
        column.axis = .vertical
        column.spacing = 6
        for row in rows {
            row.addAction(UIAction { [weak self, weak row] _ in
                guard let app = row?.app else { return }
                self?.onSelect?(app)
            }, for: .primaryActionTriggered)
        }
        return column
    }

    private func status(for app: MidgarApp, host: String?, installed: Set<String>) -> String? {
        let bundle = app.bundleId.lowercased()
        if bundle == host { return MidgarStrings.youAreHere }
        return installed.contains(bundle) ? MidgarStrings.installed : nil
    }
}

/// One app in the panel: icon, name, what they own or the tagline, and for a suggestion its price pill.
@MainActor
final class YourMidgarRowView: UIControl {
    let app: MidgarApp

    init(app: MidgarApp, owned: [OwnedItem], status: String?, priceLabel: String?) {
        self.app = app
        super.init(frame: .zero)
        backgroundColor = YourMidgarSurface.row.uiColor
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        let accent = PortalColor(hex: app.accentHex)

        let name = UILabel()
        name.text = app.shortName
        name.font = PortalFont.rounded(16, .bold)
        name.textColor = .white
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let titleRow = UIStackView(arrangedSubviews: [name])
        titleRow.spacing = 8
        titleRow.alignment = .center
        if let status {
            let chip = Self.chip(status, accent: accent)
            titleRow.addArrangedSubview(chip)
        }
        titleRow.addArrangedSubview(UIView())

        let text = UIStackView(arrangedSubviews: [titleRow, Self.details(for: app, owned: owned, accent: accent)])
        text.axis = .vertical
        text.spacing = 4
        text.alignment = .fill
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [YourMidgarIconView(app: app, side: 48 * PortalMetrics.scale), text])
        row.spacing = 12
        row.alignment = .center
        if let priceLabel { row.addArrangedSubview(Self.pricePill(priceLabel, accent: accent)) }
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = Self.spokenText(of: row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    private static func details(for app: MidgarApp, owned: [OwnedItem], accent: PortalColor) -> UIView {
        guard !owned.isEmpty else {
            let tagline = UILabel()
            tagline.text = app.tagline ?? app.genre ?? ""
            tagline.font = PortalFont.rounded(13, .regular)
            tagline.textColor = UIColor(white: 1, alpha: 0.62)
            return tagline
        }
        let lines = owned.map { item -> UIView in
            let detail = UILabel()
            detail.text = item.detail
            detail.font = PortalFont.rounded(12, .medium, monospacedDigits: true)
            detail.textColor = UIColor(white: 1, alpha: 0.7)
            detail.numberOfLines = 0
            detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let chip = chip(item.name, accent: accent)
            chip.setContentCompressionResistancePriority(.required, for: .horizontal)
            chip.setContentHuggingPriority(.required, for: .horizontal)
            let line = UIStackView(arrangedSubviews: [chip, detail])
            line.spacing = 6
            line.alignment = .firstBaseline
            return line
        }
        let column = UIStackView(arrangedSubviews: lines)
        column.axis = .vertical
        column.spacing = 3
        column.alignment = .fill
        return column
    }

    private static func chip(_ text: String, accent: PortalColor) -> UIView {
        let chip = YourMidgarChip()
        chip.configure(text: text, accent: accent)
        return chip
    }

    private static func pricePill(_ text: String, accent: PortalColor) -> UIView {
        let label = YourMidgarChip(font: PortalFont.rounded(13, .heavy), padding: UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
        label.configure(text: text, accent: nil)
        label.backgroundColor = accent.darkened(0.15).uiColor
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor(white: 1, alpha: 0.28).cgColor
        label.heightAnchor.constraint(equalToConstant: 30 * PortalMetrics.scale).isActive = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// Every label in the row, in reading order, joined for VoiceOver.
    private static func spokenText(of view: UIView) -> String {
        if let label = view as? UILabel { return label.text ?? "" }
        if let chip = view as? YourMidgarChip { return chip.text ?? "" }
        let children = (view as? UIStackView)?.arrangedSubviews ?? view.subviews
        return children.map(spokenText(of:)).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A capsule label that sizes itself for Auto Layout, used for the row's chips and price pill.
@MainActor
final class YourMidgarChip: UIView {
    private let label = UILabel()
    private let padding: UIEdgeInsets

    init(font: UIFont = PortalFont.rounded(11, .semibold), padding: UIEdgeInsets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)) {
        self.padding = padding
        super.init(frame: .zero)
        label.font = font
        label.textColor = UIColor(white: 1, alpha: 0.9)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(label)
        layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding.left),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding.right),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, constant: padding.top + padding.bottom),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var text: String? { label.text }

    override var forFirstBaselineLayout: UIView { label }

    func configure(text: String, accent: PortalColor?) {
        label.text = text
        backgroundColor = accent.map { $0.withAlpha(0.42).uiColor } ?? UIColor(white: 1, alpha: 0.12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// The app's icon: its bundled artwork at once, the App Store's when that loads, a monogram on the
/// app's colour until either does.
@MainActor
final class YourMidgarIconView: UIView {
    private let imageView = UIImageView()
    private let monogram = UILabel()

    init(app: MidgarApp, side: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        backgroundColor = PortalColor(hex: app.accentHex).darkened(0.1).uiColor
        layer.cornerRadius = side * 0.225
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        clipsToBounds = true
        isAccessibilityElement = false
        monogram.text = app.monogram
        monogram.font = PortalFont.rounded(side * 0.45 / PortalMetrics.scale, .bold)
        monogram.textColor = .white
        monogram.textAlignment = .center
        imageView.contentMode = .scaleAspectFill
        for view in [monogram, imageView] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(view)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
        load(app, side: side)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func load(_ app: MidgarApp, side: CGFloat) {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        Task { [weak self] in
            if let bundled = await midgarBundledIcon(app.appId, maxPixel: side, scale: scale) {
                self?.show(bundled)
            }
            if let remote = await midgarLoadImage(app.iconURL, maxPixel: side, scale: scale) {
                self?.show(remote)
            }
        }
    }

    private func show(_ image: UIImage) {
        imageView.image = image
        monogram.isHidden = true
    }
}
#endif
