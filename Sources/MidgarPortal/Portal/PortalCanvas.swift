#if canImport(AppKit) && !canImport(UIKit)
import SwiftUI

/// Bridges the platform canvas view into SwiftUI and keeps it in step with the model.
@MainActor
struct PortalCanvas {
    @ObservedObject var model: PortalModel
    var insets: PortalInsets

    final class Coordinator {
        var loadedIDs: [String] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    private func connect(_ view: PortalCanvasView) {
        let model = model
        view.controller.onFocusChange = { cell in
            if let id = cell.appID { model.select(appID: id) } else { model.selectCore() }
        }
        view.controller.onActivate = { cell in
            if cell.isCore {
                model.perform(.developerPage)
            } else if let id = cell.appID, let app = model.ranked.first(where: { $0.appId == id }), !model.isHost(app) {
                model.perform(model.action(for: app))
            }
        }
        view.controller.onSeen = { model.recordSeen($0) }
        view.onAccessibilityActivate = view.controller.onActivate
        view.onCancel = { model.perform(.close) }
    }

    @MainActor
    private func sync(_ view: PortalCanvasView, coordinator: Coordinator) {
        view.insets = insets
        let ids = model.ranked.map(\.appId)
        if ids != coordinator.loadedIDs {
            coordinator.loadedIDs = ids
            view.load(
                ranked: model.ranked,
                hostBundleID: model.hostBundleID,
                installed: model.installed,
                initialFocus: model.initialFocusID
            )
        } else {
            view.setInstalled(model.installed)
        }
    }
}

extension PortalCanvas: NSViewRepresentable {
    func makeNSView(context: Context) -> PortalCanvasView {
        let view = PortalCanvasView()
        connect(view)
        return view
    }

    func updateNSView(_ view: PortalCanvasView, context: Context) {
        sync(view, coordinator: context.coordinator)
    }
}
#endif
