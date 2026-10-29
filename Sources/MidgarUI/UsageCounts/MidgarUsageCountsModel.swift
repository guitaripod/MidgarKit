import Foundation
import MidgarCore

/// What the Usage Counts screen shows, as settings sections: the switch, the events this app may send, this app's public numbers when they could be read, and the link to all of Midgar's numbers.
@MainActor
final class MidgarUsageCountsModel: ObservableObject {
    static let allNumbersURL = URL(string: "https://midgarcorp.cc/open")!

    /// The registry slug of the app, or nil when the app has not configured signals.
    let appID: String?
    /// The catalog events this app sends, in registry order.
    let events: [MidgarSignalCatalog.Entry]
    /// This app's latest finished week, or nil until it is read, and for good when it cannot be: the section is then left out.
    @Published private(set) var numbers: MidgarAppNumbers?
    @Published private var revision = 0

    private let loader: any MidgarPublicStatsLoading
    private var hasStartedLoading = false
    private var switchRow: MidgarSettingsRow

    /// - Parameters:
    ///   - appID: The app's registry slug. Defaults to the one the app configured ``MidgarSignals`` with.
    ///   - catalog: The events to choose from. Defaults to the generated catalog.
    ///   - switchRow: The switch. Defaults to ``MidgarSettingsRow/usageCounts()``, which reads and sets ``MidgarSignals/isEnabled``.
    ///   - loader: Where the public numbers come from.
    init(
        appID: String? = MidgarSignals.appID,
        catalog: [MidgarSignalCatalog.Entry] = MidgarSignalCatalog.entries,
        switchRow: MidgarSettingsRow = .usageCounts(),
        loader: any MidgarPublicStatsLoading = MidgarPublicStatsClient()
    ) {
        self.appID = appID
        self.events = catalog.allowed(for: appID)
        self.loader = loader
        self.switchRow = switchRow
        self.switchRow = refreshing(switchRow)
    }

    /// Whether usage counts are on right now.
    var isEnabled: Bool {
        guard case .toggle(let get, _) = switchRow.kind else {
            return true
        }
        return get()
    }

    /// The sections in the order the screen shows them.
    var sections: [MidgarSettingsSection] {
        [switchSection, eventsSection, numbersSection, allNumbersSection].compactMap { $0 }
    }

    /// Reads the public numbers once. A failure, a timeout or an answer without this app leaves the numbers out; nothing is retried while the screen is open. Without a slug nothing is requested.
    func load() async {
        guard !hasStartedLoading, let appID else {
            return
        }
        hasStartedLoading = true
        do {
            numbers = try await loader.loadStats().latestWeek(for: appID)
        } catch {
            numbers = nil
            if Task.isCancelled {
                hasStartedLoading = false
            } else {
                MidgarLog.notice("usage counts: the public numbers could not be read", category: .network)
            }
        }
    }

    private var switchSection: MidgarSettingsSection {
        MidgarSettingsSection(id: "midgar.usageCounts.switch", footer: MidgarUIStrings.usageCountsSwitchFooter, rows: [switchRow])
    }

    private var eventsSection: MidgarSettingsSection? {
        guard !events.isEmpty else {
            return nil
        }
        return MidgarSettingsSection(
            id: "midgar.usageCounts.events",
            title: MidgarUIStrings.whatThisAppSends,
            footer: isEnabled ? nil : MidgarUIStrings.nothingIsSent,
            rows: events.map(Self.row(for:))
        )
    }

    private var numbersSection: MidgarSettingsSection? {
        guard let numbers else {
            return nil
        }
        let rows = [
            numbers.weeklyActiveInstalls.map { Self.numberRow("weekly", MidgarUIStrings.weeklyActiveInstalls, $0) },
            numbers.newInstalls.map { Self.numberRow("new", MidgarUIStrings.newInstalls, $0) }
        ].compactMap { $0 }
        return MidgarSettingsSection(
            id: "midgar.usageCounts.numbers",
            title: MidgarUIStrings.thisAppsNumbers,
            footer: MidgarUIStrings.finishedWeek(starting: numbers.weekStartingDisplay),
            rows: rows
        )
    }

    private var allNumbersSection: MidgarSettingsSection {
        MidgarSettingsSection(
            id: "midgar.usageCounts.all",
            rows: [
                .link(id: "midgar.usageCounts.all.link", title: MidgarUIStrings.allOfMidgarsNumbers, systemImage: "arrow.up.right.square", url: Self.allNumbersURL)
            ]
        )
    }

    /// One event: its purpose in plain words, then how often it can be sent and whether it carries the install week.
    private static func row(for entry: MidgarSignalCatalog.Entry) -> MidgarSettingsRow {
        var lines = [MidgarUIStrings.frequency(of: entry.uniqueness)]
        if entry.carriesCohort {
            lines.append(MidgarUIStrings.installWeekNote)
        }
        return MidgarSettingsRow(
            id: "midgar.usageCounts.event.\(entry.name)",
            title: MidgarUIStrings.purpose(of: entry),
            subtitle: lines.joined(separator: "\n")
        )
    }

    private static func numberRow(_ id: String, _ title: String, _ count: MidgarPublicStats.Count) -> MidgarSettingsRow {
        .info(id: "midgar.usageCounts.numbers.\(id)", title: title, detail: count.display)
    }

    /// The same switch, drawing the screen again after it is flipped so the list under it says whether counts are sent.
    private func refreshing(_ row: MidgarSettingsRow) -> MidgarSettingsRow {
        guard case .toggle(let get, let set) = row.kind else {
            return row
        }
        var copy = row
        copy.kind = .toggle(get: get, set: { [weak self] value in
            set(value)
            self?.revision += 1
        })
        return copy
    }
}
