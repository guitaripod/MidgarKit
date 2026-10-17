#if canImport(UIKit)
import MidgarCommerce
import MidgarUI
import SwiftUI
import UIKit

/// How a paywall presented from UIKit ended.
public enum MidgarPaywallResult: Sendable, Equatable {
    /// The customer bought something. The entitlements have changed.
    case purchased(productID: String)
    /// A restore found purchases.
    case restored
    /// The customer closed the paywall, with the close button or by swiping it away.
    case dismissed
}

/// The paywall for UIKit apps: a view controller that hosts ``MidgarPaywallScreen`` in a `UIHostingController` and calls `completion` exactly once, when a purchase or restore succeeds or the customer dismisses it.
///
/// It does not dismiss itself: the completion is the app's cue to dismiss it and unlock what was bought, so the app decides about animation and what comes next. Present it modally; it carries its own close button where the platform has one.
@available(iOS 17.0, tvOS 17.0, visionOS 1.0, *)
@MainActor
public final class MidgarPaywallViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let configuration: MidgarPaywallConfiguration
    private let store: MidgarStore
    private let theme: MidgarTheme
    private let trialPolicy: MidgarTrialPolicy
    private let showsCloseButton: Bool
    private let completion: @MainActor (MidgarPaywallResult) -> Void
    private var hasCompleted = false

    /// - Parameters:
    ///   - theme: The look of the paywall. Defaults to the theme installed with `MidgarTheme.install(_:)`.
    ///   - showsCloseButton: Whether to draw a close button. Turn it off when the app puts the paywall in a navigation controller with its own.
    ///   - completion: Called once, on the main actor.
    public init(
        configuration: MidgarPaywallConfiguration,
        store: MidgarStore,
        theme: MidgarTheme = .current,
        trialPolicy: MidgarTrialPolicy = MidgarTrialPolicy(),
        showsCloseButton: Bool = true,
        completion: @escaping @MainActor (MidgarPaywallResult) -> Void
    ) {
        self.configuration = configuration
        self.store = store
        self.theme = theme
        self.trialPolicy = trialPolicy
        self.showsCloseButton = showsCloseButton
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("MidgarPaywallViewController is created in code")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.uiBackground
        embedPaywall()
        #if !os(tvOS)
        if showsCloseButton {
            addCloseButton()
        }
        #endif
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentationController?.delegate = self
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.dismissed)
    }

    private func embedPaywall() {
        let screen = MidgarPaywallScreen(configuration: configuration, store: store, trialPolicy: trialPolicy) { [weak self] event in
            self?.handle(event)
        }
        let host = UIHostingController(rootView: screen.midgarTheme(theme))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    #if !os(tvOS)
    private func addCloseButton() {
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.image = UIImage(systemName: "xmark.circle.fill")
        buttonConfiguration.baseForegroundColor = theme.uiSecondaryLabel
        let button = UIButton(configuration: buttonConfiguration, primaryAction: UIAction { [weak self] _ in
            self?.finish(.dismissed)
        })
        button.accessibilityLabel = MidgarCommerceUIStrings.close
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: theme.spacing.s),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -theme.spacing.s)
        ])
    }
    #endif

    private func handle(_ event: MidgarPaywallEvent) {
        switch event {
        case .purchased(let productID):
            finish(.purchased(productID: productID))
        case .restored:
            finish(.restored)
        case .pending, .cancelled, .nothingToRestore, .failed:
            break
        }
    }

    private func finish(_ result: MidgarPaywallResult) {
        guard !hasCompleted else {
            return
        }
        hasCompleted = true
        completion(result)
    }
}
#endif
