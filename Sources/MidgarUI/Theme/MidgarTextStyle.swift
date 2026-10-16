import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The type scale shared by every Midgar app, one case per Dynamic Type text style.
public enum MidgarTextStyle: String, Sendable, Hashable, CaseIterable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption

    public var swiftUI: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .largeTitle, .title: .bold
        case .title2, .title3, .headline: .semibold
        case .body, .callout, .subheadline, .footnote, .caption: .regular
        }
    }

    /// The point size at the default content size category on iOS.
    var defaultPointSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        }
    }
}

/// The type design a Midgar app sets its text in.
public enum MidgarFontDesign: String, Sendable, Hashable, CaseIterable {
    case standard
    case rounded
    case serif
    case monospaced

    public var swiftUI: Font.Design {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    #if canImport(UIKit)
    var descriptorDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
    #elseif canImport(AppKit)
    var descriptorDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
    #endif
}

#if canImport(UIKit)
extension MidgarTextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        }
    }

    /// A font that scales with the user's Dynamic Type setting, in the given design.
    func uiFont(design: MidgarFontDesign) -> UIFont {
        #if os(tvOS)
        let base = UIFont.preferredFont(forTextStyle: uiKit)
        #else
        let base = UIFont.systemFont(ofSize: defaultPointSize, weight: weight.uiKit)
        #endif
        let descriptor = base.fontDescriptor.withDesign(design.descriptorDesign) ?? base.fontDescriptor
        let designed = UIFont(descriptor: descriptor, size: base.pointSize)
        #if os(tvOS)
        return designed
        #else
        return UIFontMetrics(forTextStyle: uiKit).scaledFont(for: designed)
        #endif
    }
}

extension Font.Weight {
    var uiKit: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
#endif

#if canImport(AppKit)
extension MidgarTextStyle {
    var appKit: NSFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        }
    }

    func nsFont(design: MidgarFontDesign) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: appKit)
        let base = NSFont.systemFont(ofSize: preferred.pointSize, weight: weight.appKit)
        let descriptor = base.fontDescriptor.withDesign(design.descriptorDesign) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }
}

extension Font.Weight {
    var appKit: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}
#endif
