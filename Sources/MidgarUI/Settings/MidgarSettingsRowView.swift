import SwiftUI

/// One row of `MidgarSettings`: icon, title and subtitle, a value or a switch, and a disclosure or spinner.
struct MidgarSettingsRowView: View {
    let row: MidgarSettingsRow
    let isBusy: Bool
    let revision: Int
    let engine: MidgarSettingsEngine

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        Group {
            if case .toggle(let get, _) = row.kind {
                Toggle(isOn: Binding(get: { get() }, set: { engine.setToggle(row, to: $0) })) {
                    label
                }
                .midgarSwitchToggleStyle()
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
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
            }
            textStack
            if !stacksDetailBelowTitle {
                Spacer(minLength: theme.spacing.s)
                detailText
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// At accessibility text sizes the detail drops under the title, because side by side the two would squeeze each other into a column of one word per line.
    private var stacksDetailBelowTitle: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(verbatim: row.title)
                .midgarFont(.body)
                .foregroundStyle(row.role == .destructive ? theme.destructive.color : theme.label.color)
            if let subtitle = row.subtitle {
                Text(verbatim: subtitle)
                    .midgarFont(.footnote)
                    .foregroundStyle(theme.secondaryLabel.color)
            }
            if stacksDetailBelowTitle {
                detailText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailText: some View {
        if let detail = row.detail {
            Text(verbatim: detail)
                .midgarFont(.body)
                .foregroundStyle(theme.secondaryLabel.color)
                .multilineTextAlignment(stacksDetailBelowTitle ? .leading : .trailing)
                .midgarSelectionDisabled()
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

extension View {
    /// The switch style where the platform has one; tvOS before 18 draws its own toggle.
    @ViewBuilder
    fileprivate func midgarSwitchToggleStyle() -> some View {
        #if os(tvOS)
        self
        #else
        toggleStyle(.switch)
        #endif
    }

    /// Keeps a value from being selected as text, where text selection exists.
    @ViewBuilder
    fileprivate func midgarSelectionDisabled() -> some View {
        #if os(tvOS)
        self
        #else
        textSelection(.disabled)
        #endif
    }
}
