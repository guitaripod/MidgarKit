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
                    .midgarRowInk(tint, focused: row.role == .destructive ? tint : Self.focusedInk)
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
                .midgarRowInk(
                    row.role == .destructive ? theme.destructive.color : theme.label.color,
                    focused: row.role == .destructive ? theme.destructive.color : Self.focusedInk
                )
            if let subtitle = row.subtitle {
                Text(verbatim: subtitle)
                    .midgarFont(.footnote)
                    .midgarRowInk(theme.secondaryLabel.color, focused: Self.focusedSecondaryInk)
            }
            if stacksDetailBelowTitle {
                detailText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The detail stays on one line and shrinks before it wraps: details are addresses, versions and values, and a line break inside one (with an inserted hyphen) reads as a different value. Beside the title it also wins the width it needs over the title.
    @ViewBuilder
    private var detailText: some View {
        if let detail = row.currentDetail {
            Text(verbatim: detail)
                .midgarFont(.body)
                .midgarRowInk(theme.secondaryLabel.color, focused: Self.focusedSecondaryInk)
                .multilineTextAlignment(stacksDetailBelowTitle ? .leading : .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .truncationMode(.middle)
                .layoutPriority(1)
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
                .midgarRowInk(theme.secondaryLabel.color.opacity(0.7), focused: Self.focusedSecondaryInk)
                .accessibilityHidden(true)
        }
    }

    private var tint: Color {
        row.role == .destructive ? theme.destructive.color : theme.accent.color
    }

    private static let focusedInk = Color.black.opacity(0.88)
    private static let focusedSecondaryInk = Color.black.opacity(0.62)
}

#if os(tvOS)
/// Draws `color` until the row is under the focus cursor, then `focused`: tvOS lifts a focused row on a light platter that the theme's white text would disappear into.
private struct MidgarFocusedInk: ViewModifier {
    let color: Color
    let focused: Color
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.foregroundStyle(isFocused ? focused : color)
    }
}
#endif

extension View {
    /// The row's ink, which on tvOS turns dark while the row is focused and everywhere else is `color`.
    @ViewBuilder
    fileprivate func midgarRowInk(_ color: Color, focused: Color) -> some View {
        #if os(tvOS)
        modifier(MidgarFocusedInk(color: color, focused: focused))
        #else
        foregroundStyle(color)
        #endif
    }

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
