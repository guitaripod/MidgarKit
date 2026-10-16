#if canImport(SwiftUI)
import SwiftUI

#if canImport(UIKit)
import UIKit

/// A SwiftUI wrapper around the Midgar portal, for embedding in SwiftUI hosts.
public struct MidgarStoreView: UIViewControllerRepresentable {
    private let config: MidgarConfig
    public init(config: MidgarConfig = .default) { self.config = config }
    public func makeUIViewController(context: Context) -> UIViewController { Midgar.makeStoreViewController(config: config) }
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

/// A SwiftUI wrapper around the Midgar portal, for embedding in SwiftUI hosts.
public struct MidgarStoreView: NSViewControllerRepresentable {
    private let config: MidgarConfig
    public init(config: MidgarConfig = .default) { self.config = config }
    public func makeNSViewController(context: Context) -> NSViewController { Midgar.makeStoreViewController(config: config) }
    public func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#endif

public extension View {
    /// Presents the Midgar portal when `isPresented` becomes `true`.
    ///
    /// For a self-dismissing native presentation from a button, prefer `Midgar.present()`.
    @ViewBuilder
    func midgarStore(isPresented: Binding<Bool>, config: MidgarConfig = .default) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented) {
            MidgarStoreView(config: config)
                .frame(minWidth: 640, minHeight: 600)
        }
        #else
        fullScreenCover(isPresented: isPresented) {
            MidgarStoreView(config: config).ignoresSafeArea()
        }
        #endif
    }
}
#endif
