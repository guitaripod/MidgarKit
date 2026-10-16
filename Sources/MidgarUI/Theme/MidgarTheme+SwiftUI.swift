import SwiftUI

private struct MidgarThemeKey: EnvironmentKey {
    static let defaultValue = MidgarTheme.standard
}

extension EnvironmentValues {
    public var midgarTheme: MidgarTheme {
        get { self[MidgarThemeKey.self] }
        set { self[MidgarThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a theme to this view and everything below it, and tints it with the theme's accent.
    public func midgarTheme(_ theme: MidgarTheme) -> some View {
        environment(\.midgarTheme, theme).tint(theme.accent.color)
    }

    /// Sets the text in a style of the type scale, in the environment's theme.
    public func midgarFont(_ style: MidgarTextStyle) -> some View {
        modifier(MidgarFontModifier(style: style))
    }
}

private struct MidgarFontModifier: ViewModifier {
    let style: MidgarTextStyle
    @Environment(\.midgarTheme) private var theme

    func body(content: Content) -> some View {
        content.font(theme.font(style))
    }
}
