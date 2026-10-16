import SwiftUI

/// One row of `MidgarSettings`: icon, title and subtitle, a value or a switch, and a disclosure or spinner.
struct MidgarSettingsRowView: View {
    let row: MidgarSettingsRow
    let isBusy: Bool
    let revision: Int
    let engine: MidgarSettingsEngine

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        Group {
            if case .toggle(let get, _) = row.kind {
                Toggle(isOn: Binding(get: { get() }, set: { engine.setToggle(row, to: $0) })) {
                    label
                }
                .toggleStyle(.switch)
            } else if row.isInteractive {
                Button {
                    Task { await engine.activate(row) }
                } label: {
                    HStack {
                        label
                        accessory
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityAddTraits(.isButton)
            } else {
                label
            }
        }
        .contextMenu {
            ForEach(row.menu) { item in
                Button {
                    Task { await engine.activate(item) }
                } label: {
                    if let image = item.systemImage {
                        Label(item.title, systemImage: image)
                    } else {
                        Text(verbatim: item.title)
                    }
                }
            }
        }
    }

    private var label: some View {
        HStack(spacing: theme.spacing.m) {
            if let image = row.systemImage {
                Image(systemName: image)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: row.title)
                    .midgarFont(.body)
                    .foregroundStyle(row.role == .destructive ? theme.destructive.color : theme.label.color)
                if let subtitle = row.subtitle {
                    Text(verbatim: subtitle)
                        .midgarFont(.footnote)
                        .foregroundStyle(theme.secondaryLabel.color)
                }
            }
            Spacer(minLength: theme.spacing.s)
            if let detail = row.detail {
                Text(verbatim: detail)
                    .midgarFont(.body)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.disabled)
            }
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if isBusy {
            ProgressView()
        } else if row.showsDisclosure {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryLabel.color.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    private var tint: Color {
        row.role == .destructive ? theme.destructive.color : theme.accent.color
    }
}
