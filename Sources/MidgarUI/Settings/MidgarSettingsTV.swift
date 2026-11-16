#if os(tvOS)
import SwiftUI

/// Settings on Apple TV, laid out the way the television's own Settings are: the title across the top, the rows in a
/// column on the right, and on the left a picture and a few words about whichever row has the focus. A row is one
/// line, its title on the left and its value on the right, on a platter that turns white under the focus; what a
/// phone prints under a row as a subtitle is said on the left instead, where there is room to read it from a sofa.
struct MidgarSettingsTVLayout<PortalCard: View>: View {
    let title: String
    let sections: [MidgarSettingsSection]
    let portalCard: PortalCard
    @ObservedObject var model: MidgarSettingsModel

    @Environment(\.midgarTheme) private var theme
    @FocusState private var focusedRow: String?
    /// The row the left side speaks for: the focused one, and still the last one once the focus has left the list.
    @State private var describedRow: String?
    /// True while the card under the rows has the focus. It is the host's own view, so the layout lifts it off the
    /// screen itself, and the left side stops speaking for the row above it.
    @FocusState private var portalFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.label.color)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                explanation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rows
                    .frame(width: Self.listWidth)
            }
        }
        .defaultFocus($focusedRow, firstRow, priority: .userInitiated)
        .onChange(of: focusedRow) { row in
            if let row {
                describedRow = row
            } else {
                refocusIfRowVanished()
            }
        }
    }

    /// A row can be replaced while it holds the focus, as when the row that says purchases are being checked gives
    /// way to the row for the answer. The focus goes with the row that left, and a remote with nothing under it
    /// shows no cursor, so the first row takes it. A focus that left for somewhere else is not called back.
    private func refocusIfRowVanished() {
        guard let last = describedRow, !sections.contains(where: { $0.rows.contains { $0.id == last } }),
              let first = firstRow else { return }
        describedRow = first
        Task { @MainActor in focusedRow = first }
    }

    /// The row the screen opens on, which is also the one the left side speaks for until the focus has moved.
    private var firstRow: String? {
        sections.lazy.compactMap(\.rows.first).first?.id
    }

    private static var listWidth: CGFloat { 940 }
    private static var rowInset: CGFloat { 44 }

    private var explanation: some View {
        VStack(spacing: 30) {
            RoundedRectangle(cornerRadius: 58, style: .continuous)
                .fill(LinearGradient(
                    colors: [theme.accent.color, theme.accent.color.opacity(0.62)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 260, height: 260)
                .overlay {
                    Image(systemName: described?.row.systemImage ?? "gearshape.fill")
                        .font(.system(size: 118, weight: .medium))
                        .foregroundStyle(.white)
                        .id(described?.row.systemImage ?? "gearshape.fill")
                        .transition(.opacity)
                }
                .shadow(color: .black.opacity(0.45), radius: 36, y: 20)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Text(verbatim: described?.row.title ?? title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.label.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let words = described?.words {
                    Text(verbatim: words)
                        .font(.body)
                        .foregroundStyle(theme.secondaryLabel.color)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .lineLimit(7)
                        .transition(.opacity)
                }
                if let address = described.flatMap({ Self.webAddress(of: $0.row) }) {
                    Text(verbatim: address)
                        .font(.callout.monospaced())
                        .foregroundStyle(theme.secondaryLabel.color)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 520)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 80)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.2), value: describedRow)
        .animation(.easeInOut(duration: 0.2), value: portalFocused)
    }

    /// The row the left side speaks for and the words it says: the row's own subtitle, else its section's footer.
    /// Before any row has had the focus, and when the one that had it is gone, that is the first row. While the card
    /// under the rows has the focus there is no row to speak for, and the left side shows the screen's own name.
    private var described: (row: MidgarSettingsRow, words: String?)? {
        if portalFocused { return nil }
        let spoken = sections.lazy.compactMap { section in
            section.rows.first { $0.id == describedRow }.map { ($0, $0.subtitle ?? section.footer) }
        }.first
        if let spoken { return spoken }
        guard let section = sections.first(where: { !$0.rows.isEmpty }), let row = section.rows.first else { return nil }
        return (row, row.subtitle ?? section.footer)
    }

    /// Where a row that opens a web page leads, without the scheme or the query, to be read off the screen and typed
    /// into a phone or a computer: a television has no browser to open it in.
    private static func webAddress(of row: MidgarSettingsRow) -> String? {
        guard case .link(let url) = row.kind, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host else { return nil }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        return host + path
    }

    private var rows: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    if let header = section.title {
                        Text(verbatim: header.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(theme.secondaryLabel.color)
                            .padding(.leading, 26)
                            .padding(.top, 26)
                            .padding(.bottom, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(section.rows) { row in
                        rowButton(row, footer: section.footer)
                    }
                }
                if PortalCard.self != EmptyView.self {
                    portalCard
                        .focused($portalFocused)
                        .scaleEffect(portalFocused ? 1.06 : 1)
                        .shadow(color: .black.opacity(portalFocused ? 0.5 : 0), radius: 26, y: 14)
                        .animation(.easeOut(duration: 0.16), value: portalFocused)
                        .padding(.top, 34)
                }
            }
            .padding(.horizontal, Self.rowInset)
            .padding(.top, 18)
            .padding(.bottom, 140)
        }
        .mask(Self.edgeFade)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Rows slide away under the title and off the foot of the screen instead of being cut off against an edge.
    private static var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
        }
    }

    /// A row keeps the focus while it works, showing a spinner: switching it off would send the focus to a neighbour
    /// and leave it there, and the engine already ignores a second press on a row that is busy.
    private func rowButton(_ row: MidgarSettingsRow, footer: String?) -> some View {
        Button {
            activate(row)
        } label: {
            MidgarSettingsTVRowLabel(
                row: row,
                isBusy: model.state.busyRowIDs.contains(row.id),
                revision: model.state.revision
            )
        }
        .buttonStyle(MidgarSettingsTVRowStyle())
        .focused($focusedRow, equals: row.id)
        .contextMenu {
            ForEach(Self.menu(of: row)) { item in
                Button {
                    Task { await model.engine.activate(item) }
                } label: {
                    if let image = item.systemImage {
                        Label(item.title, systemImage: image)
                    } else {
                        Text(verbatim: item.title)
                    }
                }
            }
        }
        .accessibilityHint(Text(verbatim: row.subtitle ?? footer ?? ""))
    }

    /// The items of a row's menu that mean something on a television, which has no clipboard to copy to and no
    /// mail to write: the ones that run an action.
    private static func menu(of row: MidgarSettingsRow) -> [MidgarSettingsRow.MenuItem] {
        row.menu.filter { item in
            if case .action = item.kind { true } else { false }
        }
    }

    /// Select on a switch flips it. On a row that copies its value elsewhere it does nothing, since a television has
    /// no clipboard and saying "Copied" would be untrue; the value is there to read. On any other row it does what
    /// the row does; a row that only states a fact takes the focus, so it can be read and scrolled past.
    private func activate(_ row: MidgarSettingsRow) {
        switch row.kind {
        case .toggle(let get, _):
            model.engine.setToggle(row, to: !get())
        case .copy, .info:
            return
        case .action, .link:
            Task { await model.engine.activate(row) }
        }
    }
}

/// One line of a television settings row: a symbol, the title, and on the right the row's value, On or Off for a
/// switch, a spinner while it works, or a chevron when it leads somewhere.
private struct MidgarSettingsTVRowLabel: View {
    let row: MidgarSettingsRow
    let isBusy: Bool
    let revision: Int

    @Environment(\.midgarTheme) private var theme
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 20) {
            if let image = row.systemImage {
                Image(systemName: image)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(symbolInk)
                    .frame(width: 44)
                    .accessibilityHidden(true)
            }
            Text(verbatim: row.title)
                .font(.body)
                .foregroundStyle(titleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 20)
            if let value {
                Text(verbatim: value)
                    .font(.body)
                    .foregroundStyle(valueInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            if isBusy {
                ProgressView()
            } else if row.showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(valueInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What the right of the row says: On or Off for a switch, else the row's detail.
    private var value: String? {
        if case .toggle(let get, _) = row.kind {
            return get() ? MidgarUIStrings.on : MidgarUIStrings.off
        }
        return row.currentDetail
    }

    private var titleInk: Color {
        if row.role == .destructive { return theme.destructive.color }
        return isFocused ? Self.focusedInk : theme.label.color
    }

    private var symbolInk: Color {
        if row.role == .destructive { return theme.destructive.color }
        return isFocused ? Self.focusedInk : theme.accent.color
    }

    private var valueInk: Color {
        isFocused ? Self.focusedSecondaryInk : theme.secondaryLabel.color
    }

    private static let focusedInk = Color.black.opacity(0.9)
    private static let focusedSecondaryInk = Color.black.opacity(0.6)
}

/// The platter under a television settings row: a faint one at rest, white, a little larger and lifted off the screen
/// under the focus. The growth happens inside the list's own margin, so a focused row is never cut off at its ends.
private struct MidgarSettingsTVRowStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFocused ? Color.white : Color.white.opacity(0.09))
            )
            .scaleEffect(configuration.isPressed ? 1.0 : (isFocused ? 1.035 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 22, y: 12)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
