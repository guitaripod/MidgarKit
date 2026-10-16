#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import SwiftUI

/// The portal as a sheet on macOS: hosts the SwiftUI screen and hands App Store pages and
/// installed apps off to the system.
@MainActor
public final class MidgarPortalViewController: NSViewController {
    static let preferredSize = NSSize(width: 780, height: 700)

    private let model: PortalModel
    private let hostingView: NSHostingView<PortalScreen>

    init(config: MidgarConfig) {
        model = PortalModel(config: config)
        hostingView = NSHostingView(rootView: PortalScreen(model: model))
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize
        model.onAction = { [weak self] action in self?.handle(action) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        hostingView.frame = NSRect(origin: .zero, size: Self.preferredSize)
        view = hostingView
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        model.refreshInstalled()
    }

    private func handle(_ action: PortalAction) {
        switch action {
        case .close:
            if presentingViewController != nil { presentingViewController?.dismiss(self) } else { view.window?.close() }
        case .developerPage:
            NSWorkspace.shared.open(PortalModel.developerURL)
        case .showProduct(let app), .openStore(let app), .share(let app):
            model.recordTap(app)
            NSWorkspace.shared.open(app.storeURL)
        case .launch(let app):
            model.recordTap(app)
            model.recordLaunch(app)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}
#endif
