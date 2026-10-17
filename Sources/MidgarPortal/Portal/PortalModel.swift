import Foundation
import SwiftUI

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
    @Published private(set) var yourMidgar: YourMidgarSection?
    @Published private(set) var showsYourMidgar = false

    let config: MidgarConfig
    let hostBundleID: String?
    var onAction: ((PortalAction) -> Void)?

    private let service = CatalogService()
    private let telemetry: Telemetry
    private let account: PortalAccount?
    private var accountSnapshot: PortalAccountSnapshot?
    private var loadTask: Task<Void, Never>?
    private var accountTask: Task<Void, Never>?

    /// - Parameter account: Where "Your Midgar" reads the person's apps and purchases. Defaults to the one for ``MidgarConfig/account``; without either the portal has no such section.
    init(
        config: MidgarConfig,
        hostBundleID: String? = Bundle.main.bundleIdentifier,
        account: PortalAccount? = nil,
        telemetry: Telemetry? = nil
    ) {
        self.config = config
        self.hostBundleID = hostBundleID
        self.telemetry = telemetry ?? Telemetry(config: config)
        self.account = account ?? config.account.map { PortalAccountDirectory.account(for: $0) }
    }

    var hostApp: MidgarApp? {
        ranked.first { $0.bundleId.lowercased() == hostBundleID?.lowercased() }
    }

    var availableHere: Int { ranked.filter(\.runsOnThisDevice).count }

    /// How many of the apps for this device the person has: the host, the ones installed here, and, once the identity service has answered, the ones their Midgar ID has a session or purchase in. Without that answer it is the first two, as before.
    var installedCount: Int {
        ranked.filter { $0.runsOnThisDevice && (isHost($0) || installed.contains($0.bundleId.lowercased()) || isOwned($0)) }.count
    }

    /// The registry slugs of the apps "Your Midgar" lists, empty while the account is unknown.
    private var ownedSlugs: Set<String> {
        Set(yourMidgar?.yours.compactMap(\.app.slug) ?? [])
    }

    /// `true` when the person's Midgar ID has an app that runs on this device, whether or not it is installed here. The card then offers Open, which opens the app when it is installed and its App Store page when it is not.
    func isOwned(_ app: MidgarApp) -> Bool {
        app.runsOnThisDevice && (app.slug.map(ownedSlugs.contains) ?? false)
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
        loadAccount()
    }

    func stop() {
        loadTask?.cancel()
        accountTask?.cancel()
    }

    /// Asks the identity service and the ledger what the person has. A failure leaves the portal without the section, as before.
    private func loadAccount() {
        guard let account else { return }
        accountTask = Task { [weak self] in
            let snapshot = await account.snapshot()
            guard let self, !Task.isCancelled else { return }
            accountSnapshot = snapshot
            rebuildYourMidgar()
        }
    }

    func rebuildYourMidgar() {
        yourMidgar = accountSnapshot.flatMap {
            YourMidgarBuilder.build(snapshot: $0, catalog: ranked, hostBundleID: hostBundleID, installed: installed)
        }
        if yourMidgar == nil { showsYourMidgar = false }
    }

    /// Opens the panel and counts an impression for each app it suggests.
    func showYourMidgar() {
        guard let yourMidgar else { return }
        showsYourMidgar = true
        yourMidgar.suggestions.forEach { recordSeen($0.appId) }
    }

    func hideYourMidgar() {
        showsYourMidgar = false
    }

    func refreshInstalled() {
        installed = InstalledApps.detect(in: ranked)
        rebuildYourMidgar()
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
        return isOwned(app) ? MidgarStrings.open : app.priceLabel
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
        rebuildYourMidgar()
        if case .app(let current) = selection, let fresh = ranked.first(where: { $0.appId == current.appId }) {
            selection = .app(fresh)
        }
    }
}
