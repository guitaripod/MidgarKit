#if canImport(UIKit)
import UIKit

/// An image view that asynchronously loads remote artwork with an animated shimmer placeholder,
/// cancels in-flight loads on reuse, and falls back to a bundled icon or a tinted monogram.
@MainActor
final class RemoteImageView: UIImageView {
    var onImageLoaded: ((CGSize) -> Void)?

    private var loadTask: Task<Void, Never>?
    private let monogramLabel = UILabel()
    private let shimmerLayer = CAGradientLayer()
    private var isShimmering = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        contentMode = .scaleAspectFill
        backgroundColor = .secondarySystemBackground
        isAccessibilityElement = false

        monogramLabel.textAlignment = .center
        monogramLabel.textColor = .white
        monogramLabel.adjustsFontSizeToFitWidth = true
        monogramLabel.isHidden = true
        monogramLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(monogramLabel)
        NSLayoutConstraint.activate([
            monogramLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            monogramLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        shimmerLayer.colors = [UIColor.clear.cgColor, UIColor(white: 1, alpha: 0.18).cgColor, UIColor.clear.cgColor]
        shimmerLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerLayer.locations = [0, 0.5, 1]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init() { self.init(frame: .zero) }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmerLayer.frame = bounds
        monogramLabel.font = .systemFont(ofSize: bounds.height * 0.4, weight: .bold)
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    func reset() {
        cancel()
        image = nil
        monogramLabel.isHidden = true
        backgroundColor = .secondarySystemBackground
        onImageLoaded = nil
        stopShimmer()
    }

    func loadIcon(for app: MidgarApp, accent: UIColor) {
        cancel()
        image = nil
        monogramLabel.isHidden = true
        startShimmer()
        let appId = app.appId
        let url = app.iconURL
        let monogram = app.monogram
        loadTask = Task { @MainActor [weak self] in
            let loaded = await midgarLoadImage(url) ?? midgarBundledIcon(appId)
            guard let self, !Task.isCancelled else { return }
            self.stopShimmer()
            if let loaded {
                self.image = loaded
            } else {
                self.showMonogram(monogram, accent: accent)
            }
        }
    }

    func loadScreenshot(url: URL) {
        cancel()
        image = nil
        startShimmer()
        loadTask = Task { @MainActor [weak self] in
            let loaded = await midgarLoadImage(url)
            guard let self, !Task.isCancelled else { return }
            self.stopShimmer()
            if let loaded {
                self.image = loaded
                self.onImageLoaded?(loaded.size)
            }
        }
    }

    private func showMonogram(_ text: String, accent: UIColor) {
        backgroundColor = accent
        monogramLabel.text = text
        monogramLabel.isHidden = false
    }

    private func startShimmer() {
        guard !isShimmering else { return }
        isShimmering = true
        layer.addSublayer(shimmerLayer)
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.2
        animation.repeatCount = .infinity
        shimmerLayer.add(animation, forKey: "shimmer")
    }

    private func stopShimmer() {
        guard isShimmering else { return }
        isShimmering = false
        shimmerLayer.removeAllAnimations()
        shimmerLayer.removeFromSuperlayer()
    }
}
#endif
