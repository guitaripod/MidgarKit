#if canImport(UIKit)
import UIKit

/// A horizontally scrolling strip of app screenshots. Each thumbnail keeps a fixed height and sizes
/// its width to the screenshot's aspect ratio once loaded.
@MainActor
final class ScreenshotStripView: UIView {
    static let preferredHeight: CGFloat = 188

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var imageViews: [RemoteImageView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            heightAnchor.constraint(equalToConstant: Self.preferredHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init() { self.init(frame: .zero) }

    func reset() {
        imageViews.forEach { $0.reset() }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
    }

    func configure(urls: [URL]) {
        reset()
        for url in urls.prefix(10) {
            let imageView = RemoteImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.layer.cornerRadius = 12
            imageView.layer.cornerCurve = .continuous
            imageView.layer.borderWidth = 0.5
            imageView.layer.borderColor = UIColor.separator.withAlphaComponent(0.5).cgColor

            let widthConstraint = imageView.widthAnchor.constraint(equalToConstant: Self.preferredHeight * 0.56)
            widthConstraint.isActive = true
            imageView.onImageLoaded = { [weak widthConstraint] size in
                guard let widthConstraint, size.height > 0 else { return }
                widthConstraint.constant = (Self.preferredHeight * size.width / size.height).rounded()
            }

            stack.addArrangedSubview(imageView)
            imageView.loadScreenshot(url: url)
            imageViews.append(imageView)
        }
    }
}
#endif
