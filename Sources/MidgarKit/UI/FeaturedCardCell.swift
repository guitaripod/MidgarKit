#if canImport(UIKit)
import UIKit

/// A large editorial card for a featured app: an oversized icon over a backdrop drawn from the
/// app's own artwork, with the name, tagline and price pill beneath.
///
/// The app's first screenshot is blurred into a backdrop rather than shown crisp: these are
/// marketing shots with their own padding and captions, so any crop of one reads as a fragment.
/// When no screenshot is available the card falls back to a gradient tinted from the app's accent.
@MainActor
final class FeaturedCardCell: UICollectionViewCell {
    static let preferredHeight: CGFloat = 360

    private let artwork = RemoteImageView()
    private let backdrop = CAGradientLayer()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let heroIconShadow = UIView()
    private let heroIcon = RemoteImageView()
    private let scrim = CAGradientLayer()
    private let icon = RemoteImageView()
    private let nameLabel = UILabel()
    private let taglineLabel = UILabel()
    private let pill = UILabel()
    private var accent: UIColor = .systemBlue

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.reset()
        heroIcon.reset()
        icon.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = contentView.bounds
        backdrop.frame = contentView.bounds
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    func configure(with app: MidgarApp, accent: UIColor) {
        self.accent = accent
        let tint = UIColor(hex: app.accentHex) ?? accent

        // Screenshots here are *marketing* shots — their own padding, device frames and captions.
        // Cropping one into this card shows a meaningless middle slice and puts the title over
        // whatever bright UI happens to land there. Blurring it into a backdrop keeps the app's
        // real colour and texture while the crisp icon stays the subject.
        if let first = app.screenshotURLs.first {
            artwork.isHidden = false
            blurView.isHidden = false
            artwork.loadScreenshot(url: first, maxPixel: Self.preferredHeight)
        } else {
            artwork.isHidden = true
            blurView.isHidden = true
        }
        heroIcon.loadIcon(for: app, accent: tint, maxPixel: 132)
        backdrop.colors = [
            tint.withAlphaComponent(0.62).cgColor,
            tint.withAlphaComponent(0.28).cgColor,
        ]
        icon.loadIcon(for: app, accent: tint, maxPixel: 56)
        nameLabel.text = app.name
        taglineLabel.text = app.tagline
        taglineLabel.isHidden = (app.tagline ?? "").isEmpty
        pill.text = "  \(app.priceLabel.uppercased())  "

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = midgarAccessibilityText(for: app)
        accessibilityHint = "Opens the App Store product page"
    }

    private func setup() {
        contentView.layer.cornerRadius = 22
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = .secondarySystemBackground

        artwork.contentMode = .scaleAspectFill
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blurView)

        // Added after the blur so it tints the blurred screenshot rather than sitting under it —
        // an ultra-thin blur alone leaves the card nearly monochrome.
        backdrop.startPoint = CGPoint(x: 0.1, y: 0)
        backdrop.endPoint = CGPoint(x: 0.9, y: 1)
        contentView.layer.addSublayer(backdrop)

        // The shadow has to live on a container: `heroIcon` clips to its corner radius, and a
        // layer cannot both mask its contents and cast a shadow.
        heroIconShadow.translatesAutoresizingMaskIntoConstraints = false
        heroIconShadow.layer.shadowColor = UIColor.black.cgColor
        heroIconShadow.layer.shadowOpacity = 0.33
        heroIconShadow.layer.shadowRadius = 18
        heroIconShadow.layer.shadowOffset = CGSize(width: 0, height: 10)
        contentView.addSubview(heroIconShadow)

        heroIcon.translatesAutoresizingMaskIntoConstraints = false
        heroIcon.layer.cornerRadius = 29
        heroIcon.layer.cornerCurve = .continuous
        heroIconShadow.addSubview(heroIcon)

        // Weighted hard towards the bottom third: the title and tagline sit over whatever the
        // screenshot happens to contain, which is frequently light, busy UI.
        scrim.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.10).cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.black.withAlphaComponent(0.94).cgColor,
        ]
        scrim.locations = [0, 0.38, 0.78, 1]
        contentView.layer.addSublayer(scrim)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.layer.cornerRadius = 12
        icon.layer.cornerCurve = .continuous
        icon.layer.borderWidth = 0.5
        icon.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor

        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 1

        taglineLabel.font = .preferredFont(forTextStyle: .footnote)
        taglineLabel.adjustsFontForContentSizeCategory = true
        taglineLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        taglineLabel.numberOfLines = 2

        pill.font = UIFont.preferredFont(forTextStyle: .footnote).midgarBold
        pill.adjustsFontForContentSizeCategory = true
        pill.textColor = .white
        pill.textAlignment = .center
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        pill.layer.cornerRadius = 14
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.setContentCompressionResistancePriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [nameLabel, taglineLabel])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, text, pill])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            heroIconShadow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            heroIconShadow.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -24),
            heroIconShadow.widthAnchor.constraint(equalToConstant: 132),
            heroIconShadow.heightAnchor.constraint(equalToConstant: 132),
            heroIcon.topAnchor.constraint(equalTo: heroIconShadow.topAnchor),
            heroIcon.bottomAnchor.constraint(equalTo: heroIconShadow.bottomAnchor),
            heroIcon.leadingAnchor.constraint(equalTo: heroIconShadow.leadingAnchor),
            heroIcon.trailingAnchor.constraint(equalTo: heroIconShadow.trailingAnchor),

            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            pill.heightAnchor.constraint(equalToConstant: 28),

            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }
}
#endif
