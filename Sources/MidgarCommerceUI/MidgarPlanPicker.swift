import MidgarUI
import SwiftUI

/// Where the keyboard or remote focus is on a plan paywall.
enum MidgarPaywallFocus: Hashable {
    case plan(String)
    case purchase
    case restore
}

/// One choice for every plan, subscriptions and one-time products together: the selected plan is drawn with the accent, and on tvOS the selection follows the focus.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPlanPicker: View {
    let plans: [MidgarPlan]
    let selectedID: String?
    let isEnabled: Bool
    let select: (String) -> Void
    let focus: FocusState<MidgarPaywallFocus?>.Binding

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            ForEach(plans) { plan in
                MidgarPlanChoice(plan: plan, isSelected: plan.id == selectedID) {
                    select(plan.id)
                    #if os(tvOS)
                    focus.wrappedValue = .purchase
                    #endif
                }
                .focused(focus, equals: .plan(plan.id))
            }
        }
        .disabled(!isEnabled)
        .modifier(MidgarSelectionFeedback(trigger: selectedID))
        .accessibilityElement(children: .contain)
    }
}

/// A plan as a card: a selection marker, the name with its badge, the detail lines and the price.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPlanChoice: View {
    let plan: MidgarPlan
    let isSelected: Bool
    var focusOverride: Bool?
    let action: () -> Void

    @Environment(\.midgarTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            layout
                .padding(.horizontal, theme.spacing.l)
                .padding(.vertical, Self.verticalPadding(theme))
                .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .leading)
        }
        .buttonStyle(MidgarPlanChoiceStyle(isSelected: isSelected, focusOverride: focusOverride))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private static func verticalPadding(_ theme: MidgarTheme) -> CGFloat {
        #if os(tvOS)
        theme.spacing.xl
        #else
        theme.spacing.m + theme.spacing.xxs
        #endif
    }

    private static var minimumHeight: CGFloat {
        #if os(visionOS)
        60
        #else
        0
        #endif
    }

    @ViewBuilder
    private var layout: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                HStack(alignment: .top, spacing: theme.spacing.m) {
                    marker
                    titleBlock
                }
                priceText
            }
        } else {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                marker
                titleBlock
                Spacer(minLength: theme.spacing.s)
                priceText
            }
        }
    }

    private var marker: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: Self.markerSize))
            .foregroundStyle(isSelected ? theme.accent.color : theme.secondaryLabel.color.opacity(0.7))
            .accessibilityHidden(true)
    }

    private static var markerSize: CGFloat {
        #if os(tvOS)
        32
        #else
        24
        #endif
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.s) {
                Text(verbatim: plan.name)
                    .midgarFont(.headline)
                    .foregroundStyle(theme.label.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let badge = plan.badge {
                    badgeView(badge)
                }
            }
            ForEach(plan.detailLines, id: \.self) { line in
                Text(verbatim: line)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.secondaryLabel.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var priceText: some View {
        Text(verbatim: plan.displayPrice)
            .midgarFont(.headline)
            .foregroundStyle(theme.label.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badgeView(_ badge: String) -> some View {
        Text(verbatim: badge)
            .midgarFont(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(theme.label.color)
            .padding(.horizontal, theme.spacing.s)
            .padding(.vertical, theme.spacing.xxs)
            .background(theme.accent.color.opacity(0.28), in: Capsule())
            .fixedSize()
    }
}

/// The card around a plan choice: the theme's surface, a thin separator when idle, the accent border when selected, and on tvOS a lifted card with a bright border while focused.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPlanChoiceStyle: ButtonStyle {
    let isSelected: Bool
    /// Draws the focused look whatever the focus engine says, so a screenshot can show it. Nil follows the real focus.
    var focusOverride: Bool?

    @Environment(\.midgarTheme) private var theme
    @Environment(\.isFocused) private var focusedByEngine
    @Environment(\.isEnabled) private var isEnabled

    private var isFocused: Bool {
        focusOverride ?? focusedByEngine
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(MidgarPlanChoiceFill(isSelected: isSelected, isFocused: isFocused, shape: shape))
            .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
            .contentShape(.interaction, shape)
            .scaleEffect(scale(isPressed: configuration.isPressed))
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 16, y: 8)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .modifier(MidgarPlanHover(shape: shape))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    private var borderColor: Color {
        if isFocused {
            return theme.label.color.opacity(0.9)
        }
        return isSelected ? theme.accent.color : theme.separator.color
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return 4
        }
        return isSelected ? 2 : 1
    }

    private func scale(isPressed: Bool) -> CGFloat {
        if isPressed {
            return 0.98
        }
        return isFocused ? 1.03 : 1
    }
}

private struct MidgarPlanHover<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content.contentShape(.hoverEffect, shape).hoverEffect()
        #else
        content
        #endif
    }
}

/// A tick of selection feedback when the selected plan changes, where the OS has it (visionOS 26 and later, every other platform from 17).
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarSelectionFeedback: ViewModifier {
    let trigger: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        if #available(visionOS 26.0, *) {
            content.sensoryFeedback(.selection, trigger: trigger)
        } else {
            content
        }
        #else
        content.sensoryFeedback(.selection, trigger: trigger)
        #endif
    }
}

/// What fills a plan card: the theme's surface, tinted with the accent when selected, and on tvOS lighter while focused.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarPlanChoiceFill<S: Shape>: ViewModifier {
    let isSelected: Bool
    let isFocused: Bool
    let shape: S

    @Environment(\.midgarTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content.background(theme.surface.color.opacity(isFocused ? 1 : 0.7), in: shape)
        #else
        content.background(isSelected ? theme.accent.color.opacity(0.08) : theme.surface.color, in: shape)
        #endif
    }
}
