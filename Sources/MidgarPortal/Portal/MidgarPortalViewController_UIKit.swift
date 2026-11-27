#if canImport(UIKit)
import Combine
import StoreKit
import UIKit

/// The portal as a view controller, built from UIKit views over a Core Animation canvas: the
/// backdrop, the honeycomb, a slim header, the card describing what sits at the centre and, on
/// touch screens, "Your Midgar". It presents App Store product pages, launches installed apps and
/// shares links to apps that live on another platform.
@MainActor
public final class MidgarPortalViewController: UIViewController {
    private let model: PortalModel
    private let irisDelegate: PortalIrisTransitioning
    private let backdrop = PortalBackdropView()
    private let canvas = PortalCanvasView()
    private let header = PortalHeaderView()
    private let card = PortalCardView()
    #if !os(tvOS)
    private var panel: YourMidgarPanelView?
    #endif
    private var modelChanges: AnyCancellable?
    private var needsModelSync = true
    private var loadedIDs: [String] = []
    private var countedFor: (ids: [String], installed: Set<String>, yourMidgar: YourMidgarSection?)?
    private var isRunning = false
    private var presentingProduct = false

    convenience init(config: MidgarConfig, irisOrigin: CGPoint? = nil) {
        self.init(model: PortalModel(config: config), irisOrigin: irisOrigin)
    }

    init(model: PortalModel, irisOrigin: CGPoint? = nil) {
        self.model = model
        irisDelegate = PortalIrisTransitioning(origin: irisOrigin)
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = irisDelegate
        overrideUserInterfaceStyle = .dark
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

    public override var preferredFocusEnvironments: [any UIFocusEnvironment] { [canvas] }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PortalColor.space.uiColor
        view.maximumContentSizeCategory = .accessibilityMedium
        for subview in [backdrop, canvas, header, card] as [UIView] { view.addSubview(subview) }
        connectCanvas()
        connectChrome()
        modelChanges = model.objectWillChange.sink { [weak self] _ in self?.setNeedsModelSync() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshInstalled),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !isRunning {
            isRunning = true
            model.start()
        }
        model.refreshInstalled()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isRunning = false
        model.stop()
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if needsModelSync { syncFromModel() }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = view.safeAreaInsets
        let layout = PortalScreenLayout(
            size: view.bounds.size,
            safeArea: PortalSafeArea(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        )
        backdrop.frame = view.bounds
        canvas.frame = view.bounds
        canvas.insets = layout.canvasInsets
        header.frame = layout.headerFrame
        card.frame = layout.cardFrame
        #if !os(tvOS)
        if let panel {
            let room = layout.panelBounds
            let height = min(panel.naturalHeight(forWidth: room.width), room.height)
            panel.frame = CGRect(x: room.minX, y: room.minY, width: room.width, height: height)
        }
        #endif
    }

    #if !os(tvOS)
    public override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeFromKeyboard))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape]
    }

    @objc private func closeFromKeyboard() {
        model.perform(.close)
    }
    #endif

    /// Marks the screen stale after any model change. The work happens once, in the next layout
    /// pass of the same frame, however many properties changed.
    private func setNeedsModelSync() {
        needsModelSync = true
        viewIfLoaded?.setNeedsLayout()
    }

    @objc private func refreshInstalled() {
        model.refreshInstalled()
    }

    /// Runs on every focus change while a finger drags, so it reads each published value once and
    /// recounts the header only when what it counts has changed.
    private func syncFromModel() {
        needsModelSync = false
        let ranked = model.ranked
        let installed = model.installed
        let yourMidgar = model.yourMidgar
        let ids = ranked.map { $0.appId }
        if ids != loadedIDs {
            loadedIDs = ids
            canvas.load(ranked: ranked, hostBundleID: model.hostBundleID, installed: installed, initialFocus: model.initialFocusID)
        } else {
            canvas.setInstalled(installed)
        }
        let counted = countedFor.map { $0.ids == ids && $0.installed == installed && $0.yourMidgar == yourMidgar } ?? false
        if !counted {
            countedFor = (ids, installed, yourMidgar)
            header.subtitle = MidgarStrings.installedCount(model.installedCount, of: model.availableHere)
        }
        #if !os(tvOS)
        header.showsYourMidgar = yourMidgar != nil
        #endif
        let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
        backdrop.setAccent(model.accent, animated: animate)
        card.show(cardContent(for: model.selection), animated: animate)
        #if !os(tvOS)
        syncPanel(animated: animate)
        #endif
    }

    private func cardContent(for selection: PortalSelection) -> PortalCardContent {
        switch selection {
        case .core:
            return PortalCardContent(
                title: "Midgar Oy",
                body: MidgarStrings.coreBlurb,
                bodyLines: 0,
                rating: nil,
                chips: [],
                button: PortalCardContent.Button(title: MidgarStrings.allApps, accent: .midgar)
            )
        case .app(let app):
            let accent = PortalColor(hex: app.accentHex)
            var chips: [PortalCardContent.Chip] = []
            if model.isHost(app) {
                chips.append(PortalCardContent.Chip(text: MidgarStrings.youAreHere, accent: accent))
            } else if model.isInstalled(app) {
                chips.append(PortalCardContent.Chip(text: MidgarStrings.installed, accent: accent))
            }
            if let genre = app.genre { chips.append(PortalCardContent.Chip(text: genre, accent: nil)) }
            return PortalCardContent(
                title: app.shortName,
                body: app.tagline ?? app.genre ?? "",
                bodyLines: 2,
                rating: app.hasRating ? (app.rating ?? 0).formatted(.number.precision(.fractionLength(1))) : nil,
                chips: chips,
                button: model.buttonTitle(for: app).map { PortalCardContent.Button(title: $0, accent: accent) }
            )
        }
    }

    private func connectCanvas() {
        let model = model
        canvas.controller.onFocusChange = { cell in
            if let id = cell.appID { model.select(appID: id) } else { model.selectCore() }
        }
        canvas.controller.onActivate = { cell in
            if cell.isCore {
                model.perform(.developerPage)
            } else if let id = cell.appID, let app = model.ranked.first(where: { $0.appId == id }), !model.isHost(app) {
                model.perform(model.action(for: app))
            }
        }
        canvas.controller.onSeen = { model.recordSeen($0) }
        canvas.onAccessibilityActivate = canvas.controller.onActivate
    }

    private func connectChrome() {
        let model = model
        card.button.addAction(UIAction { _ in
            switch model.selection {
            case .core: model.perform(.developerPage)
            case .app(let app): model.perform(model.action(for: app))
            }
        }, for: .primaryActionTriggered)
        #if !os(tvOS)
        header.closeButton.addAction(UIAction { _ in model.perform(.close) }, for: .primaryActionTriggered)
        header.yourMidgarButton.addAction(UIAction { _ in
            if model.showsYourMidgar { model.hideYourMidgar() } else { model.showYourMidgar() }
        }, for: .primaryActionTriggered)
        #endif
    }

    #if !os(tvOS)
    private func syncPanel(animated: Bool) {
        guard model.showsYourMidgar, let section = model.yourMidgar else {
            guard let panel else { return }
            self.panel = nil
            UIView.animate(withDuration: animated ? 0.2 : 0, animations: { panel.alpha = 0 }, completion: { _ in panel.removeFromSuperview() })
            return
        }
        let shown = panel ?? makePanel()
        shown.configure(section: section, hostBundleID: model.hostBundleID, installed: model.installed)
        guard shown.superview == nil else { return }
        panel = shown
        shown.alpha = 0
        view.addSubview(shown)
        view.setNeedsLayout()
        UIView.animate(withDuration: animated ? 0.2 : 0) { shown.alpha = 1 }
    }

    private func makePanel() -> YourMidgarPanelView {
        let model = model
        let panel = YourMidgarPanelView()
        panel.onSelect = { app in
            if !model.isHost(app) { model.perform(model.action(for: app)) }
        }
        panel.onClose = { model.hideYourMidgar() }
        return panel
    }
    #endif

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
            if let url = InstalledApps.installedURL(for: app) ?? InstalledApps.launchURL(for: app) {
                UIApplication.shared.open(url)
            }
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
        sheet.popoverPresentationController?.sourceView = card.button
        sheet.popoverPresentationController?.sourceRect = card.button.bounds
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
        model.refreshInstalled()
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
        animation.preferredFrameRateRange = PortalFrameRate.motion
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
