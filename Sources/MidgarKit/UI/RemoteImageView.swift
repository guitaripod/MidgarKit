#if canImport(UIKit)
import UIKit

/// An image view that asynchronously loads remote artwork downsampled to its own size, cancels
/// in-flight loads on reuse, and falls back to a bundled icon or a tinted monogram.
///
/// The target size is passed in rather than read from `bounds` so a load can start before the first
/// layout pass — during prefetch, the view has no frame yet.
@MainActor
final class RemoteImageView: UIImageView {
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
        layer.allowsGroupOpacity = false

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
        alpha = 1
        monogramLabel.isHidden = true
        backgroundColor = .secondarySystemBackground
        stopShimmer()
    }

    func loadIcon(for app: MidgarApp, accent: UIColor, maxPixel: CGFloat) {
        cancel()
        image = nil
        monogramLabel.isHidden = true
        startShimmer()
        let appId = app.appId
        let url = app.iconURL
        let monogram = app.monogram
        let scale = traitCollection.displayScale
        loadTask = Task { @MainActor [weak self] in
            var loaded = await midgarLoadImage(url, maxPixel: maxPixel, scale: scale)
            if loaded == nil {
                loaded = await midgarBundledIcon(appId, maxPixel: maxPixel, scale: scale)
            }
            guard let self, !Task.isCancelled else { return }
            self.stopShimmer()
            if let loaded {
                self.set(loaded)
            } else {
                self.showMonogram(monogram, accent: accent)
            }
        }
    }

    func loadScreenshot(url: URL, maxPixel: CGFloat) {
        cancel()
        image = nil
        startShimmer()
        let scale = traitCollection.displayScale
        loadTask = Task { @MainActor [weak self] in
            let loaded = await midgarLoadImage(url, maxPixel: maxPixel, scale: scale)
            guard let self, !Task.isCancelled, let loaded else { return }
            self.stopShimmer()
            self.set(loaded)
        }
    }

    private func set(_ loaded: UIImage) {
        image = loaded
        alpha = 0
        UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut) { self.alpha = 1 }
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
