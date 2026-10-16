import SwiftUI

extension View {
    /// Fills the view with Liquid Glass on iOS, macOS and tvOS 26 and later, and with a thin material before that and on visionOS, whose glass background needs an insettable shape.
    public func midgarGlass<S: Shape>(in shape: S) -> some View {
        modifier(MidgarGlassModifier(shape: shape))
    }
}

private struct MidgarGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content.background(.ultraThinMaterial, in: shape)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #endif
    }
}

extension View {
    /// A filled button in the accent: glass-prominent on iOS, macOS and tvOS 26 and later, bordered-prominent elsewhere. visionOS has no glass-prominent style.
    @ViewBuilder
    func midgarProminentButtonStyle() -> some View {
        #if os(visionOS)
        buttonStyle(.borderedProminent)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #endif
    }
}
