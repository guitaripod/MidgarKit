import SwiftUI

extension View {
    /// Fills the view with Liquid Glass on iOS, macOS, tvOS and visionOS 26 and later, and with a thin material before that.
    public func midgarGlass<S: Shape>(in shape: S) -> some View {
        modifier(MidgarGlassModifier(shape: shape))
    }
}

private struct MidgarGlassModifier<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}
