#if canImport(UIKit)
import UIKit

@MainActor
final class EmptyStateView: UIView {
    private let onRetry: () -> Void

    init(accent: UIColor, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        super.init(frame: .zero)

        let imageView = UIImageView(image: UIImage(systemName: "square.grid.2x2"))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .light)

        let title = UILabel()
        title.text = "Nothing here yet"
        title.font = .preferredFont(forTextStyle: .headline)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Check your connection and try again."
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let retry = UIButton(type: .system)
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = accent.withAlphaComponent(0.14)
        configuration.baseForegroundColor = accent
        configuration.title = "Retry"
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24)
        retry.configuration = configuration
        retry.addAction(UIAction { [weak self] _ in self?.onRetry() }, for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [imageView, title, subtitle, retry])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
#endif
