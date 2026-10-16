#if canImport(UIKit)
import UIKit

/// Shows toasts over UIKit content. One toast is visible per host view; a new one replaces the old.
@MainActor
public enum MidgarToastPresenter {
    public static func show(_ toast: MidgarToast, in host: UIView, theme: MidgarTheme = .current) {
        host.subviews.compactMap { $0 as? MidgarToastUIView }.forEach { $0.dismiss(animated: false) }
        let view = MidgarToastUIView(toast: toast, theme: theme)
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: host.safeAreaLayoutGuide.centerXAnchor),
            view.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -theme.spacing.xl),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: host.layoutMarginsGuide.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: host.layoutMarginsGuide.trailingAnchor)
        ])
        view.present()
        MidgarAnnouncer.announce(toast.message)
        if let haptic = toast.style.haptic { MidgarHaptics.shared.play(haptic) }
    }
}

extension UIViewController {
    /// Shows a toast over this controller's view.
    public func showMidgarToast(_ toast: MidgarToast, theme: MidgarTheme = .current) {
        MidgarToastPresenter.show(toast, in: view, theme: theme)
    }
}

@MainActor
final class MidgarToastUIView: UIView {
    private let toast: MidgarToast
    private let effectView = UIVisualEffectView()
    private var dismissTask: Task<Void, Never>?

    init(toast: MidgarToast, theme: MidgarTheme) {
        self.toast = toast
        super.init(frame: .zero)
        configureEffect()
        configureContent(theme: theme)
        alpha = 0
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = toast.message
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        let offset: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0 : 16
        transform = CGAffineTransform(translationX: 0, y: offset)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1
            self.transform = .identity
        }
        dismissTask = Task { [weak self, duration = toast.duration] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(animated: true)
        }
    }

    func dismiss(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        guard animated else { return removeFromSuperview() }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }

    /// Glass on 26 and later, a system material before that.
    private func configureEffect() {
        if #available(iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            effectView.effect = UIGlassEffect()
        } else {
            effectView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.clipsToBounds = true
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func configureContent(theme: MidgarTheme) {
        let icon = UIImageView(image: UIImage(systemName: toast.systemImage))
        icon.tintColor = tint(theme: theme)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = toast.message
        label.font = theme.uiFont(.subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = theme.uiLabel
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = theme.spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: theme.spacing.m),
            stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -theme.spacing.m),
            stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: theme.spacing.l),
            stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -theme.spacing.l)
        ])
    }

    private func tint(theme: MidgarTheme) -> UIColor {
        switch toast.style {
        case .info: theme.uiAccent
        case .success: .systemGreen
        case .warning: .systemOrange
        case .error: theme.uiDestructive
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        effectView.layer.cornerRadius = bounds.height / 2
    }
}
#endif
