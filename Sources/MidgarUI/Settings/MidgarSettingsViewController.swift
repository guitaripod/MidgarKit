#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// The UIKit settings screen of a Midgar app: an optional portal card on top, then sections of rows.
/// Push it on a navigation controller; it sets its own title.
@MainActor
public final class MidgarSettingsViewController: UIViewController {
    public var sections: [MidgarSettingsSection] {
        didSet {
            guard isViewLoaded else { return }
            tableView.reloadData()
        }
    }

    public var theme: MidgarTheme {
        didSet {
            guard isViewLoaded else { return }
            applyTheme()
            tableView.reloadData()
        }
    }

    private let portalCardView: UIView?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let engine: MidgarSettingsEngine
    private var portalCell: UITableViewCell?
    private var hostedCard: UIHostingController<AnyView>?
    private var isShowingAlert = false
    private var lastToastID: UUID?

    private static let rowIdentifier = "MidgarSettingsRow"
    private static let toggleIdentifier = "MidgarSettingsToggleRow"

    /// Settings with a UIKit view as the portal card, or none.
    public init(
        title: String? = nil,
        sections: [MidgarSettingsSection],
        portalCardView: UIView? = nil,
        theme: MidgarTheme = .current
    ) {
        self.sections = sections
        self.portalCardView = portalCardView
        self.theme = theme
        self.engine = MidgarSettingsEngine()
        super.init(nibName: nil, bundle: nil)
        self.title = title ?? MidgarUIStrings.settings
    }

    /// Settings with a SwiftUI view as the portal card.
    public convenience init<Card: View>(
        title: String? = nil,
        sections: [MidgarSettingsSection],
        theme: MidgarTheme = .current,
        @ViewBuilder portalCard: @escaping @MainActor () -> Card
    ) {
        self.init(title: title, sections: sections, portalCardView: nil, theme: theme)
        self.swiftUIPortalCard = { AnyView(portalCard().midgarTheme(theme)) }
    }

    private var swiftUIPortalCard: (@MainActor () -> AnyView)?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.rowIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.toggleIdentifier)
        tableView.estimatedRowHeight = 52
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        applyTheme()
        engine.onChange = { [weak self] state in self?.render(state) }
    }

    private var hasPortalCard: Bool {
        portalCardView != nil || swiftUIPortalCard != nil
    }

    private func applyTheme() {
        view.backgroundColor = theme.uiBackground
        tableView.backgroundColor = theme.uiBackground
        tableView.separatorColor = theme.uiSeparator
        view.tintColor = theme.uiAccent
    }

    private func row(at indexPath: IndexPath) -> MidgarSettingsRow {
        sections[indexPath.section - (hasPortalCard ? 1 : 0)].rows[indexPath.row]
    }

    private func section(_ index: Int) -> MidgarSettingsSection {
        sections[index - (hasPortalCard ? 1 : 0)]
    }

    private func isPortalSection(_ index: Int) -> Bool {
        hasPortalCard && index == 0
    }

    /// Builds the portal cell once: the card pinned inside a clear cell.
    private func makePortalCell() -> UITableViewCell {
        if let portalCell { return portalCell }
        let cell = UITableViewCell()
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        let card = resolvePortalCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor)
        ])
        portalCell = cell
        return cell
    }

    private func resolvePortalCard() -> UIView {
        if let portalCardView { return portalCardView }
        guard let swiftUIPortalCard else { return UIView() }
        let host = UIHostingController(rootView: swiftUIPortalCard())
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        addChild(host)
        host.didMove(toParent: self)
        hostedCard = host
        return host.view
    }

    private func configure(_ cell: UITableViewCell, with row: MidgarSettingsRow) {
        var content: UIListContentConfiguration = row.detail != nil ? .valueCell() : .subtitleCell()
        content.text = row.title
        content.secondaryText = row.detail ?? row.subtitle
        content.textProperties.font = theme.uiFont(.body)
        content.textProperties.color = row.role == .destructive ? theme.uiDestructive : theme.uiLabel
        content.secondaryTextProperties.font = theme.uiFont(row.detail != nil ? .body : .footnote)
        content.secondaryTextProperties.color = theme.uiSecondaryLabel
        if let name = row.systemImage {
            content.image = UIImage(systemName: name)
            content.imageProperties.tintColor = row.role == .destructive ? theme.uiDestructive : theme.uiAccent
        }
        cell.contentConfiguration = content
        var background = UIBackgroundConfiguration.listGroupedCell()
        background.backgroundColor = theme.uiSurface
        cell.backgroundConfiguration = background
        cell.selectionStyle = row.isInteractive ? .default : .none
        cell.isUserInteractionEnabled = !engine.state.busyRowIDs.contains(row.id)
        cell.accessoryView = nil
        cell.accessoryType = .none
        applyAccessibilityTraits(to: cell, for: row)
        applyAccessory(to: cell, for: row)
    }

    /// Buttons and static text get their trait. A toggle row has its own reuse identifier and keeps the traits UIKit derives from its switch, so VoiceOver announces a switch and not a button.
    private func applyAccessibilityTraits(to cell: UITableViewCell, for row: MidgarSettingsRow) {
        if case .toggle = row.kind {
            return
        }
        cell.accessibilityTraits = row.isInteractive ? .button : .staticText
    }

    private func applyAccessory(to cell: UITableViewCell, for row: MidgarSettingsRow) {
        if engine.state.busyRowIDs.contains(row.id) {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessoryView = spinner
        } else if case .toggle(let get, _) = row.kind {
            let toggle = UISwitch()
            toggle.isOn = get()
            toggle.onTintColor = theme.uiAccent
            toggle.addAction(
                UIAction { [weak self, weak toggle] _ in
                    guard let self, let toggle else { return }
                    self.engine.setToggle(row, to: toggle.isOn)
                },
                for: .valueChanged
            )
            cell.accessoryView = toggle
        } else if row.showsDisclosure {
            cell.accessoryType = .disclosureIndicator
        }
    }

    private func render(_ state: MidgarSettingsEngine.State) {
        reloadVisibleRows()
        presentToastIfNew(state.toast)
        presentConfirmationIfNeeded(state.pending)
        presentFailureIfNeeded(state.failureMessage)
    }

    private func reloadVisibleRows() {
        let visible = (tableView.indexPathsForVisibleRows ?? []).filter { !isPortalSection($0.section) }
        for indexPath in visible {
            guard let cell = tableView.cellForRow(at: indexPath) else { continue }
            configure(cell, with: row(at: indexPath))
        }
    }

    private func presentToastIfNew(_ toast: MidgarToast?) {
        guard let toast, toast.id != lastToastID else { return }
        lastToastID = toast.id
        showMidgarToast(toast, theme: theme)
    }

    private func presentConfirmationIfNeeded(_ pending: MidgarSettingsEngine.PendingConfirmation?) {
        guard let pending, !isShowingAlert else { return }
        isShowingAlert = true
        let alert = UIAlertController(
            title: pending.confirmation.title,
            message: pending.confirmation.message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: MidgarUIStrings.cancel, style: .cancel) { [weak self] _ in
            self?.isShowingAlert = false
            self?.engine.cancelPending()
        })
        alert.addAction(UIAlertAction(title: pending.confirmation.confirmTitle, style: .destructive) { [weak self] _ in
            self?.isShowingAlert = false
            self?.engine.beginConfirmedAction()
        })
        present(alert, animated: true)
    }

    private func presentFailureIfNeeded(_ message: String?) {
        guard let message, !isShowingAlert else { return }
        isShowingAlert = true
        let alert = UIAlertController(title: MidgarUIStrings.failureTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: MidgarUIStrings.ok, style: .cancel) { [weak self] _ in
            self?.isShowingAlert = false
            self?.engine.dismissFailure()
        })
        present(alert, animated: true)
    }
}

extension MidgarSettingsViewController: UITableViewDataSource, UITableViewDelegate {
    public func numberOfSections(in tableView: UITableView) -> Int {
        sections.count + (hasPortalCard ? 1 : 0)
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        isPortalSection(section) ? 1 : self.section(section).rows.count
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        isPortalSection(section) ? nil : self.section(section).title
    }

    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        isPortalSection(section) ? nil : self.section(section).footer
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isPortalSection(indexPath.section) { return makePortalCell() }
        let row = self.row(at: indexPath)
        let identifier: String
        if case .toggle = row.kind {
            identifier = Self.toggleIdentifier
        } else {
            identifier = Self.rowIdentifier
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        configure(cell, with: row)
        return cell
    }

    public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        !isPortalSection(indexPath.section) && row(at: indexPath).isInteractive
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isPortalSection(indexPath.section) else { return }
        let row = row(at: indexPath)
        Task { await engine.activate(row) }
    }

    public func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isPortalSection(indexPath.section) else { return nil }
        let items = row(at: indexPath).menu
        guard !items.isEmpty else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: items.map { item in
                UIAction(title: item.title, image: item.systemImage.flatMap { UIImage(systemName: $0) }) { _ in
                    Task { await self?.engine.activate(item) }
                }
            })
        }
    }
}
#endif
