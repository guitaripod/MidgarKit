#if canImport(UIKit)
import UIKit

@MainActor
final class AppCell: UICollectionViewCell {
    private let icon = RemoteImageView()
    private let featuredLabel = UILabel()
    private let titleLabel = UILabel()
    private let taglineLabel = UILabel()
    private let metaLabel = UILabel()
    private let getButton = UIButton(type: .system)
    private let strip = ScreenshotStripView()
    private let separator = UIView()

    private var onGet: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        icon.reset()
        strip.reset()
        onGet = nil
    }

    func configure(with app: MidgarApp, accent: UIColor, onGet: @escaping () -> Void) {
        self.onGet = onGet

        icon.loadIcon(for: app, accent: accent)

        featuredLabel.isHidden = !app.featured
        if app.featured {
            let featuredFont = UIFontMetrics(forTextStyle: .caption2)
                .scaledFont(for: .systemFont(ofSize: 11, weight: .heavy))
            featuredLabel.attributedText = NSAttributedString(
                string: "FEATURED",
                attributes: [.font: featuredFont, .foregroundColor: accent, .kern: 0.6]
            )
        }

        titleLabel.text = app.name
        taglineLabel.text = app.tagline
        taglineLabel.isHidden = (app.tagline ?? "").isEmpty
        metaLabel.attributedText = metaText(for: app)

        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = accent.withAlphaComponent(0.14)
        configuration.baseForegroundColor = accent
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        configuration.title = app.priceLabel.uppercased()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .footnote).bold
            return outgoing
        }
        getButton.configuration = configuration

        if app.screenshotURLs.isEmpty {
            strip.isHidden = true
        } else {
            strip.isHidden = false
            strip.configure(urls: app.screenshotURLs)
        }

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = accessibilityText(for: app)
        accessibilityHint = "Opens the App Store product page"
    }

    private func setup() {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.layer.cornerRadius = 13.5
        icon.layer.cornerCurve = .continuous
        icon.layer.borderWidth = 0.5
        icon.layer.borderColor = UIColor.separator.withAlphaComponent(0.4).cgColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
        ])

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        taglineLabel.font = .preferredFont(forTextStyle: .subheadline)
        taglineLabel.adjustsFontForContentSizeCategory = true
        taglineLabel.textColor = .secondaryLabel
        taglineLabel.numberOfLines = 2

        metaLabel.numberOfLines = 1
        metaLabel.adjustsFontForContentSizeCategory = true
        featuredLabel.adjustsFontForContentSizeCategory = true
        getButton.titleLabel?.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [featuredLabel, titleLabel, taglineLabel, metaLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        getButton.setContentHuggingPriority(.required, for: .horizontal)
        getButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        getButton.addAction(UIAction { [weak self] _ in self?.onGet?() }, for: .primaryActionTriggered)

        let topRow = UIStackView(arrangedSubviews: [icon, textStack, getButton])
        topRow.axis = .horizontal
        topRow.spacing = 12
        topRow.alignment = .center

        let main = UIStackView(arrangedSubviews: [topRow, strip])
        main.axis = .vertical
        main.spacing = 12
        main.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(main)

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            main.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            main.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            main.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func metaText(for app: MidgarApp) -> NSAttributedString {
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

    private func accessibilityText(for app: MidgarApp) -> String {
        var parts = [app.name]
        if let tagline = app.tagline, !tagline.isEmpty { parts.append(tagline) }
        if app.hasRating, let rating = app.rating {
            parts.append(String(format: "rated %.1f stars", rating))
        }
        parts.append(app.priceLabel == "GET" ? "Free" : app.priceLabel)
        return parts.joined(separator: ", ")
    }
}

private extension UIFont {
    var bold: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
#endif
