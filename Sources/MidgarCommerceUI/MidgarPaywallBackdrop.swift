import MidgarUI
import SwiftUI

/// The name of the coordinate space the paywall measures its backdrop in.
enum MidgarPaywallSpace {
    static let name = "midgar.paywall"
}

/// A backdrop gradient and the size of the paywall it is drawn across.
struct MidgarPaywallBackdrop: Equatable {
    let colors: [MidgarColor]
    /// The size of the paywall inside its safe area, which is what the layout sees.
    let size: CGSize
    /// The safe area around it. The background ignores the safe area, so the gradient spans the size and the insets together.
    let insets: EdgeInsets
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarPaywallBackdropKey: EnvironmentKey {
    static let defaultValue: MidgarPaywallBackdrop? = nil
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
extension EnvironmentValues {
    var midgarPaywallBackdrop: MidgarPaywallBackdrop? {
        get { self[MidgarPaywallBackdropKey.self] }
        set { self[MidgarPaywallBackdropKey.self] = newValue }
    }
}

/// The gradient across the paywall, from its top leading corner to its bottom trailing one.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarBackdropGradient: View {
    let colors: [MidgarColor]

    var body: some View {
        LinearGradient(colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The part of the backdrop that lies behind this view, so a pinned bar with an opaque surface still looks like part of the page.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
private struct MidgarBackdropSlice: View {
    let backdrop: MidgarPaywallBackdrop

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(MidgarPaywallSpace.name))
            let insets = backdrop.insets
            MidgarBackdropGradient(colors: backdrop.colors)
                .frame(width: backdrop.size.width + insets.leading + insets.trailing, height: backdrop.size.height + insets.top + insets.bottom)
                .offset(x: -insets.leading - frame.minX, y: -insets.top - frame.minY)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
    }
}

/// The paywall's own background: the theme's, with the app's backdrop over it. On visionOS the window's glass is the background.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPaywallBackground: ViewModifier {
    let colors: [MidgarColor]

    @Environment(\.midgarTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
        #else
        content.background {
            ZStack {
                theme.background.color
                if !colors.isEmpty {
                    MidgarBackdropGradient(colors: colors)
                }
            }
            .ignoresSafeArea()
        }
        #endif
    }
}

/// The opaque surface behind the pinned purchase bar, so nothing scrolls visibly behind it: the theme's background with the part of the backdrop that lies there. On visionOS the bar is a system bar over the window's glass.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, *)
struct MidgarPinnedSurface: ViewModifier {
    @Environment(\.midgarTheme) private var theme
    @Environment(\.midgarPaywallBackdrop) private var backdrop

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content.background(.bar)
        #else
        content.background {
            ZStack {
                theme.background.color
                if let backdrop, !backdrop.colors.isEmpty {
                    MidgarBackdropSlice(backdrop: backdrop)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        #endif
    }
}
