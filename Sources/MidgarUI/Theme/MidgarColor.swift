import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A color that has one value in light appearance and one in dark, independent of any UI framework.
public struct MidgarColor: Sendable, Hashable {
    /// A color in the sRGB space with components from 0 to 1.
    public struct RGBA: Sendable, Hashable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Reads `0xRRGGBB` as opaque sRGB.
        public init(hex: UInt32, alpha: Double = 1) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: alpha
            )
        }
    }

    public var light: RGBA
    public var dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public init(lightHex: UInt32, darkHex: UInt32) {
        self.init(light: RGBA(hex: lightHex), dark: RGBA(hex: darkHex))
    }

    /// One color for both appearances.
    public init(hex: UInt32) {
        self.init(lightHex: hex, darkHex: hex)
    }

    public func resolved(isDark: Bool) -> RGBA {
        isDark ? dark : light
    }

    /// The same color with its alpha multiplied by `opacity` in both appearances.
    public func opacity(_ opacity: Double) -> MidgarColor {
        var light = light
        var dark = dark
        light.alpha *= opacity
        dark.alpha *= opacity
        return MidgarColor(light: light, dark: dark)
    }

    public var color: Color {
        #if canImport(UIKit)
        Color(uiColor: uiColor)
        #else
        Color(nsColor: nsColor)
        #endif
    }
}

#if canImport(UIKit)
extension MidgarColor {
    /// A dynamic `UIColor` that follows the interface style of the trait collection it is drawn in.
    public var uiColor: UIColor {
        let light = light
        let dark = dark
        return UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }
    }
}
#endif

#if canImport(AppKit)
extension MidgarColor {
    /// A dynamic `NSColor` that follows the effective appearance it is drawn in.
    public var nsColor: NSColor {
        let light = light
        let dark = dark
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }
    }
}
#endif
