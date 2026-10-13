import MidgarKit
import SwiftUI
import UIKit

/// A stand-in for a host app's settings screen, used to try the portal and the entry card on a
/// real device.
final class SettingsDemoViewController: UITableViewController {
    private enum Row: Int, CaseIterable {
        case entryCard
        case swiftUICard
        case directPresent
        case version
    }

    init() {
        super.init(style: .insetGrouped)
        title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        switch Row(rawValue: indexPath.row)! {
        case .entryCard:
            embed(MidgarEntryView(), in: cell)
        case .swiftUICard:
            let host = UIHostingController(rootView: MidgarEntryCard())
            host.view.backgroundColor = .clear
            addChild(host)
            embed(host.view, in: cell)
            host.didMove(toParent: self)
        case .directPresent:
            var content = cell.defaultContentConfiguration()
            content.text = "Open the portal directly"
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
        case .version:
            var content = cell.defaultContentConfiguration()
            content.text = "Midgar Demo 1.0"
            content.textProperties.color = .secondaryLabel
            cell.contentConfiguration = content
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if Row(rawValue: indexPath.row) == .directPresent {
            Midgar.present(from: self)
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Row(rawValue: indexPath.row)! {
        case .entryCard, .swiftUICard: return MidgarEntryView.preferredHeight + 20
        default: return 52
        }
    }

    private func embed(_ view: UIView, in cell: UITableViewCell) {
        view.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
            view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
            view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
        ])
    }
}
