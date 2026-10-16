import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The distances between and inside elements, in points.
public struct MidgarSpacing: Sendable, Hashable {
    public var xxs: CGFloat = 2
    public var xs: CGFloat = 4
    public var s: CGFloat = 8
    public var m: CGFloat = 12
    public var l: CGFloat = 16
    public var xl: CGFloat = 24
    public var xxl: CGFloat = 32

    public init() {}
}

/// Corner radii, in points.
public struct MidgarRadius: Sendable, Hashable {
    public var small: CGFloat = 8
    public var medium: CGFloat = 12
    public var large: CGFloat = 16
    public var card: CGFloat = 20

    public init() {}
}

/// The look of one Midgar app: its accent, the semantic colors, the type design, spacing and corner radii.
/// Every MidgarUI component reads the theme from the SwiftUI environment or, in UIKit, from `MidgarTheme.current`.
public struct MidgarTheme: Sendable, Hashable {
    public static let defaultAccent = MidgarColor(lightHex: 0x5B5BD6, darkHex: 0x8E8EF0)

    public var accent: MidgarColor
    public var background: MidgarColor
    public var surface: MidgarColor
    public var label: MidgarColor
    public var secondaryLabel: MidgarColor
    public var separator: MidgarColor
    public var destructive: MidgarColor
    public var success: MidgarColor
    public var warning: MidgarColor
    public var fontDesign: MidgarFontDesign
    public var spacing: MidgarSpacing
    public var radius: MidgarRadius

    public init(
        accent: MidgarColor = MidgarTheme.defaultAccent,
        background: MidgarColor = MidgarColor(lightHex: 0xF2F2F7, darkHex: 0x000000),
        surface: MidgarColor = MidgarColor(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E),
        label: MidgarColor = MidgarColor(lightHex: 0x000000, darkHex: 0xFFFFFF),
        secondaryLabel: MidgarColor = MidgarColor(
            light: MidgarColor.RGBA(hex: 0x3C3C43, alpha: 0.6),
            dark: MidgarColor.RGBA(hex: 0xEBEBF5, alpha: 0.6)
        ),
        separator: MidgarColor = MidgarColor(
            light: MidgarColor.RGBA(hex: 0x3C3C43, alpha: 0.29),
            dark: MidgarColor.RGBA(hex: 0x545458, alpha: 0.6)
        ),
        destructive: MidgarColor = MidgarColor(lightHex: 0xFF3B30, darkHex: 0xFF453A),
        success: MidgarColor = MidgarColor(lightHex: 0x34C759, darkHex: 0x30D158),
        warning: MidgarColor = MidgarColor(lightHex: 0xFF9500, darkHex: 0xFF9F0A),
        fontDesign: MidgarFontDesign = .standard,
        spacing: MidgarSpacing = MidgarSpacing(),
        radius: MidgarRadius = MidgarRadius()
    ) {
        self.accent = accent
        self.background = background
        self.surface = surface
        self.label = label
        self.secondaryLabel = secondaryLabel
        self.separator = separator
        self.destructive = destructive
        self.success = success
        self.warning = warning
        self.fontDesign = fontDesign
        self.spacing = spacing
        self.radius = radius
    }

    public static let standard = MidgarTheme()

    public func font(_ style: MidgarTextStyle) -> Font {
        .system(style.swiftUI, design: fontDesign.swiftUI, weight: style.weight)
    }
}

extension MidgarTheme {
    /// The theme UIKit components use. Set it once at launch; SwiftUI components read the environment instead.
    @MainActor public static var current = MidgarTheme.standard

    @MainActor public static func install(_ theme: MidgarTheme) {
        current = theme
    }
}

#if canImport(UIKit)
extension MidgarTheme {
    public var uiAccent: UIColor { accent.uiColor }
    public var uiBackground: UIColor { background.uiColor }
    public var uiSurface: UIColor { surface.uiColor }
    public var uiLabel: UIColor { label.uiColor }
    public var uiSecondaryLabel: UIColor { secondaryLabel.uiColor }
    public var uiSeparator: UIColor { separator.uiColor }
    public var uiDestructive: UIColor { destructive.uiColor }
    public var uiSuccess: UIColor { success.uiColor }
    public var uiWarning: UIColor { warning.uiColor }

    public func uiFont(_ style: MidgarTextStyle) -> UIFont {
        style.uiFont(design: fontDesign)
    }
}
#endif

#if canImport(AppKit)
extension MidgarTheme {
    public var nsAccent: NSColor { accent.nsColor }
    public var nsBackground: NSColor { background.nsColor }
    public var nsSurface: NSColor { surface.nsColor }
    public var nsLabel: NSColor { label.nsColor }
    public var nsSecondaryLabel: NSColor { secondaryLabel.nsColor }
    public var nsSeparator: NSColor { separator.nsColor }
    public var nsDestructive: NSColor { destructive.nsColor }
    public var nsSuccess: NSColor { success.nsColor }
    public var nsWarning: NSColor { warning.nsColor }

    public func nsFont(_ style: MidgarTextStyle) -> NSFont {
        style.nsFont(design: fontDesign)
    }
}
#endif
