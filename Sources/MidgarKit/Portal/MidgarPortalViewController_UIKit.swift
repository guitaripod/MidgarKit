#if canImport(UIKit)
import StoreKit
import SwiftUI
import UIKit

/// The portal as a view controller: hosts the SwiftUI screen, presents App Store product pages,
/// launches installed apps and shares links to apps that live on another platform.
@MainActor
public final class MidgarPortalViewController: UIViewController {
    private let model: PortalModel
    private let hosting: UIHostingController<PortalScreen>
    private let irisDelegate: PortalIrisTransitioning
    private var presentingProduct = false

    init(config: MidgarConfig, irisOrigin: CGPoint? = nil) {
        irisDelegate = PortalIrisTransitioning(origin: irisOrigin)
        model = PortalModel(config: config)
        hosting = UIHostingController(rootView: PortalScreen(model: model))
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = irisDelegate
        #if !os(tvOS)
        modalPresentationCapturesStatusBarAppearance = true
        #endif
        model.onAction = { [weak self] action in self?.handle(action) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    #if !os(tvOS)
    public override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    #endif

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.02, green: 0.025, blue: 0.07, alpha: 1)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.refreshInstalled()
    }

    private func handle(_ action: PortalAction) {
        switch action {
        case .close:
            close()
        case .developerPage:
            UIApplication.shared.open(PortalModel.developerURL)
        case .showProduct(let app):
            model.recordTap(app)
            presentProduct(app)
        case .launch(let app):
            model.recordTap(app)
            model.recordLaunch(app)
            if let url = InstalledApps.launchURL(for: app) { UIApplication.shared.open(url) }
        case .share(let app):
            model.recordTap(app)
            share(app)
        case .openStore(let app):
            model.recordTap(app)
            UIApplication.shared.open(app.storeURL)
        }
    }

    private func close() {
        if let navigation = navigationController, navigation.viewControllers.first !== self {
            navigation.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func share(_ app: MidgarApp) {
        #if os(tvOS)
        UIApplication.shared.open(app.storeURL)
        #else
        let sheet = UIActivityViewController(activityItems: [app.storeURL], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 120, width: 1, height: 1)
        present(sheet, animated: true)
        #endif
    }

    private func presentProduct(_ app: MidgarApp) {
        guard !presentingProduct, presentedViewController == nil else { return }
        #if os(iOS)
        presentingProduct = true
        let product = SKStoreProductViewController()
        product.delegate = self
        var parameters: [String: Any] = [
            SKStoreProductParameterITunesItemIdentifier: app.appId,
            SKStoreProductParameterCampaignToken: model.config.campaignToken,
        ]
        if let provider = model.config.providerToken {
            parameters[SKStoreProductParameterProviderToken] = provider
        }
        product.loadProduct(withParameters: parameters) { [weak self] success, _ in
            guard let self else { return }
            if success {
                self.model.recordLoaded(app)
                self.present(product, animated: true)
            } else {
                self.presentingProduct = false
                UIApplication.shared.open(app.storeURL)
            }
        }
        #else
        UIApplication.shared.open(app.storeURL)
        #endif
    }
}

#if os(iOS)
extension MidgarPortalViewController: @MainActor SKStoreProductViewControllerDelegate {
    public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        presentingProduct = false
        viewController.dismiss(animated: true)
    }
}
#endif

/// Opens the portal like an iris: a circle grows from the middle of the screen, where the Midgar
/// core sits, and closes back into it on dismissal.
final class PortalIrisTransitioning: NSObject, UIViewControllerTransitioningDelegate {
    private let origin: CGPoint?

    init(origin: CGPoint?) { self.origin = origin }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        PortalIrisAnimator(opening: true, origin: origin)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PortalIrisAnimator(opening: false, origin: origin)
    }
}

final class PortalIrisAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let opening: Bool
    private let origin: CGPoint?

    init(opening: Bool, origin: CGPoint?) {
        self.opening = opening
        self.origin = origin
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        opening ? 0.62 : 0.42
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView
        guard let portalView = transitionContext.view(forKey: opening ? .to : .from) else {
            transitionContext.completeTransition(false)
            return
        }
        if opening {
            portalView.frame = container.bounds
            container.addSubview(portalView)
        } else if let underneath = transitionContext.view(forKey: .to), underneath.superview == nil {
            container.insertSubview(underneath, at: 0)
        }

        let centre = origin ?? CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        let reach = max(
            hypot(centre.x, centre.y), hypot(container.bounds.width - centre.x, centre.y),
            hypot(centre.x, container.bounds.height - centre.y),
            hypot(container.bounds.width - centre.x, container.bounds.height - centre.y)
        ) + 20
        let small = Self.circle(centre: centre, radius: 6)
        let large = Self.circle(centre: centre, radius: reach)
        let mask = CAShapeLayer()
        mask.path = opening ? large : small
        portalView.layer.mask = mask

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = opening ? small : large
        animation.toValue = opening ? large : small
        animation.duration = transitionDuration(using: transitionContext)
        animation.timingFunction = CAMediaTimingFunction(name: opening ? .easeOut : .easeIn)
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            portalView.layer.mask = nil
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
        mask.add(animation, forKey: "iris")
        CATransaction.commit()
    }

    private static func circle(centre: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(
            ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
    }
}
#endif
