#if canImport(UIKit)
import UIKit

/// A compact storefront row: icon, name, tagline, rating and price pill.
///
/// Deliberately carries no screenshot strip. The previous row rebuilt ten image views and ten
/// layout constraints on every reuse and mutated a width constraint as each thumbnail landed,
/// which re-measured the self-sizing cell mid-scroll. Screenshots now live only on the featured
/// cards, where there is one per app.
@MainActor
final class AppRowCell: UICollectionViewCell {
    private let icon = RemoteImageView()
    private let titleLabel = UILabel()
    private let taglineLabel = UILabel()
    private let metaLabel = UILabel()
    private let pill = PillLabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        icon.reset()
    }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? .systemFill : .clear }
    }

    func configure(with app: MidgarApp, accent: UIColor) {
        icon.loadIcon(for: app, accent: accent, maxPixel: 60)
        titleLabel.text = app.name
        taglineLabel.text = app.tagline
        taglineLabel.isHidden = (app.tagline ?? "").isEmpty
        metaLabel.attributedText = midgarMetaText(for: app)
        metaLabel.isHidden = metaLabel.attributedText?.length == 0

        pill.text = app.priceLabel.uppercased()
        pill.textColor = accent
        pill.backgroundColor = accent.withAlphaComponent(0.14)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = midgarAccessibilityText(for: app)
        accessibilityHint = "Opens the App Store product page"
    }

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.layer.cornerRadius = 13.5
        icon.layer.cornerCurve = .continuous
        icon.layer.borderWidth = 0.5
        icon.layer.borderColor = UIColor.separator.withAlphaComponent(0.4).cgColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        taglineLabel.font = .preferredFont(forTextStyle: .subheadline)
        taglineLabel.adjustsFontForContentSizeCategory = true
        taglineLabel.textColor = .secondaryLabel
        taglineLabel.numberOfLines = 2

        metaLabel.numberOfLines = 1
        metaLabel.adjustsFontForContentSizeCategory = true

        pill.font = UIFont.preferredFont(forTextStyle: .footnote).midgarBold
        pill.adjustsFontForContentSizeCategory = true
        pill.textAlignment = .center
        pill.layer.cornerRadius = 14
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.setContentCompressionResistancePriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [titleLabel, taglineLabel, metaLabel])
        text.axis = .vertical
        text.spacing = 3
        text.alignment = .leading
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, text, pill])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
            pill.heightAnchor.constraint(equalToConstant: 28),

            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 88),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}

/// A plain section header — "Featured" / "All Apps".
@MainActor
final class SectionHeaderView: UICollectionReusableView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = UIFont.preferredFont(forTextStyle: .title2).midgarBold
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        label.text = title
    }
}

func midgarMetaText(for app: MidgarApp) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let caption = UIFont.preferredFont(forTextStyle: .caption1)
    if app.hasRating, let rating = app.rating {
        result.append(NSAttributedString(
            string: "★ ",
            attributes: [.foregroundColor: UIColor.systemYellow, .font: caption]
        ))
        var ratingText = String(format: "%.1f", rating)
        if let count = app.ratingCount, count > 0 { ratingText += " (\(count))" }
        result.append(NSAttributedString(
            string: ratingText,
            attributes: [.foregroundColor: UIColor.secondaryLabel, .font: caption]
        ))
    }
    if let genre = app.genre, !genre.isEmpty {
        if result.length > 0 {
            result.append(NSAttributedString(
                string: "  ·  ",
                attributes: [.foregroundColor: UIColor.tertiaryLabel, .font: caption]
            ))
        }
        result.append(NSAttributedString(
            string: genre,
            attributes: [.foregroundColor: UIColor.secondaryLabel, .font: caption]
        ))
    }
    return result
}

func midgarAccessibilityText(for app: MidgarApp) -> String {
    var parts = [app.name]
    if let tagline = app.tagline, !tagline.isEmpty { parts.append(tagline) }
    if app.hasRating, let rating = app.rating {
        parts.append(String(format: "rated %.1f stars", rating))
    }
    parts.append(app.priceLabel == "GET" ? "Free" : app.priceLabel)
    return parts.joined(separator: ", ")
}

extension UIFont {
    var midgarBold: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
#endif
