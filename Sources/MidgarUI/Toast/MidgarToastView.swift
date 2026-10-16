import SwiftUI

/// The toast capsule: an icon and one line of text on glass.
public struct MidgarToastView: View {
    public let toast: MidgarToast

    @Environment(\.midgarTheme) private var theme

    public init(_ toast: MidgarToast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: toast.message)
                .midgarFont(.subheadline)
                .foregroundStyle(theme.label.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, theme.spacing.l)
        .padding(.vertical, theme.spacing.m)
        .midgarGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch toast.style {
        case .info: theme.accent.color
        case .success: theme.success.color
        case .warning: theme.warning.color
        case .error: theme.destructive.color
        }
    }
}

extension View {
    /// Shows `toast` at the bottom of this view while it is non-nil, then clears it after its duration.
    public func midgarToast(_ toast: Binding<MidgarToast?>) -> some View {
        modifier(MidgarToastModifier(toast: toast))
    }
}

private struct MidgarToastModifier: ViewModifier {
    @Binding var toast: MidgarToast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.midgarTheme) private var theme

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    MidgarToastView(toast)
                        .padding(.bottom, theme.spacing.xl)
                        .padding(.horizontal, theme.spacing.l)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .id(toast.id)
                        .allowsHitTesting(false)
                }
            }
            .animation(.snappy, value: toast?.id)
            .task(id: toast?.id) { await dismissAfterDuration() }
    }

    /// Announces the toast, plays its haptic and clears the binding once the toast has been up for its duration.
    private func dismissAfterDuration() async {
        guard let current = toast else { return }
        MidgarAnnouncer.announce(current.message)
        if let haptic = current.style.haptic { MidgarHaptics.shared.play(haptic) }
        try? await Task.sleep(for: .seconds(current.duration))
        guard !Task.isCancelled, toast?.id == current.id else { return }
        toast = nil
    }
}
