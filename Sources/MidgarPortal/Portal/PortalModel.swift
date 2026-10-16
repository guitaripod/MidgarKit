import Foundation
import MidgarUI

/// What the bottom card is describing.
enum PortalSelection: Hashable {
    case core
    case app(MidgarApp)
}

/// The things a card button or a tapped icon can ask the host to do.
enum PortalAction {
    case showProduct(MidgarApp)
    case launch(MidgarApp)
    case share(MidgarApp)
    case openStore(MidgarApp)
    case developerPage
    case close
}

/// State behind the portal screen: the ranked catalog, what is installed, what is focused.
@MainActor
final class PortalModel: ObservableObject {
    static let developerURL = URL(string: "https://apps.apple.com/developer/midgar-oy/id1484270247")!

    @Published private(set) var ranked: [MidgarApp] = []
    @Published private(set) var installed: Set<String> = []
    @Published var selection: PortalSelection = .core
    @Published private(set) var accent = PortalColor.midgar

    let config: MidgarConfig
    let hostBundleID: String?
    var onAction: ((PortalAction) -> Void)?

    private let service = CatalogService()
    private let telemetry: Telemetry
    private var loadTask: Task<Void, Never>?

    init(config: MidgarConfig, hostBundleID: String? = Bundle.main.bundleIdentifier) {
        self.config = config
        self.hostBundleID = hostBundleID
        self.telemetry = Telemetry(config: config)
    }

    var hostApp: MidgarApp? {
        ranked.first { $0.bundleId.lowercased() == hostBundleID?.lowercased() }
    }

    var availableHere: Int { ranked.filter(\.runsOnThisDevice).count }

    var installedCount: Int {
        ranked.filter { $0.runsOnThisDevice && ($0.bundleId.lowercased() == hostBundleID?.lowercased() || installed.contains($0.bundleId.lowercased())) }.count
    }

    /// The app the camera should drift to once the portal has opened.
    var initialFocusID: String? { ranked.first { $0.appId != hostApp?.appId }?.appId }

    func start() {
        telemetry.send(.portalOpen)
        let cached = service.cachedSnapshot()
        apply(withoutExcluded(cached.isEmpty ? CatalogService.bundledApps() : cached))
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await service.buildIncludingHost(config: config)
            guard !Task.isCancelled, !result.isEmpty else { return }
            if Set(result.map(\.appId)) != Set(ranked.map(\.appId)) { apply(withoutExcluded(result)) }
        }
    }

    func stop() {
        loadTask?.cancel()
    }

    func refreshInstalled() {
        installed = InstalledApps.detect(in: ranked)
    }

    func select(_ selection: PortalSelection) {
        self.selection = selection
        switch selection {
        case .core: accent = .midgar
        case .app(let app): accent = PortalColor(hex: app.accentHex)
        }
    }

    func selectCore() { select(.core) }

    func select(appID: String) {
        guard let app = ranked.first(where: { $0.appId == appID }) else { return }
        select(.app(app))
    }

    func recordSeen(_ appID: String) {
        telemetry.send(.impression, appId: appID)
    }

    func recordTap(_ app: MidgarApp) {
        telemetry.send(.tap, appId: app.appId)
    }

    func recordLoaded(_ app: MidgarApp) {
        telemetry.send(.loaded, appId: app.appId)
    }

    func recordLaunch(_ app: MidgarApp) {
        telemetry.send(.launch, appId: app.appId)
    }

    func isInstalled(_ app: MidgarApp) -> Bool {
        installed.contains(app.bundleId.lowercased())
    }

    func isHost(_ app: MidgarApp) -> Bool {
        app.bundleId.lowercased() == hostBundleID?.lowercased()
    }

    /// What the card's button should do for `app` on this device.
    func action(for app: MidgarApp) -> PortalAction {
        if isInstalled(app) { return .launch(app) }
        if !app.runsOnThisDevice {
            #if os(iOS)
            return .share(app)
            #else
            return .openStore(app)
            #endif
        }
        return .showProduct(app)
    }

    func buttonTitle(for app: MidgarApp) -> String? {
        if isHost(app) { return nil }
        if isInstalled(app) { return MidgarStrings.open }
        if let foreign = app.foreignPlatform {
            #if os(iOS)
            return MidgarStrings.sendTo(foreign.badgeLabel.uppercased())
            #else
            return MidgarStrings.view
            #endif
        }
        return app.priceLabel
    }

    func perform(_ action: PortalAction) {
        onAction?(action)
    }

    private func withoutExcluded(_ apps: [MidgarApp]) -> [MidgarApp] {
        let excluded = Set(config.excludedBundleIDs.map { $0.lowercased() })
        return apps.filter { !excluded.contains($0.bundleId.lowercased()) }
    }

    private func apply(_ apps: [MidgarApp]) {
        let installedNow = InstalledApps.detect(in: apps)
        installed = installedNow
        ranked = PortalRanking.order(apps: apps, hostBundleID: hostBundleID, installed: installedNow)
        InstalledApps.warnIfSchemesMissing(for: apps)
        if case .app(let current) = selection, let fresh = ranked.first(where: { $0.appId == current.appId }) {
            selection = .app(fresh)
        }
    }
}
