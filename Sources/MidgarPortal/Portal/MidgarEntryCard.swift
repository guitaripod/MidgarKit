import MidgarUI
#if canImport(SwiftUI)

/// SwiftUI form of ``MidgarEntryView``: the card with the live miniature of the portal. Place it in
/// a `List` section or a form; tapping it opens the portal.
public struct MidgarEntryCard {
    private let config: MidgarConfig

    public init(config: MidgarConfig = MidgarConfig(placement: "entry")) {
        self.config = config
    }
}

#if canImport(UIKit)
extension MidgarEntryCard: UIViewRepresentable {
    public func makeUIView(context: Context) -> MidgarEntryView {
        let view = MidgarEntryView(config: config)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    public func updateUIView(_ uiView: MidgarEntryView, context: Context) {}

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: MidgarEntryView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 360, height: MidgarEntryView.preferredHeight)
    }
}
#else
extension MidgarEntryCard: NSViewRepresentable {
    public func makeNSView(context: Context) -> MidgarEntryView {
        MidgarEntryView(config: config)
    }

    public func updateNSView(_ nsView: MidgarEntryView, context: Context) {}

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: MidgarEntryView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 360, height: MidgarEntryView.preferredHeight)
    }
}
#endif
#endif
