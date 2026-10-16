import SwiftUI

#if canImport(UIKit)
import UIKit

/// Onboarding as a full-screen UIKit controller. It marks the store completed and calls `onFinish` when the person is done.
@MainActor
public final class MidgarOnboardingViewController: UIHostingController<AnyView> {
    public init(
        pages: [MidgarOnboardingPage],
        store: MidgarOnboardingStore? = nil,
        showsSkip: Bool = true,
        theme: MidgarTheme = .current,
        onFinish: @escaping @MainActor () -> Void
    ) {
        let root = MidgarOnboarding(pages: pages, store: store, showsSkip: showsSkip, onFinish: onFinish)
        super.init(rootView: AnyView(root.midgarTheme(theme)))
        modalPresentationStyle = .fullScreen
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#endif

extension View {
    /// Covers this view with onboarding until the store says it was completed.
    public func midgarOnboarding(
        pages: [MidgarOnboardingPage],
        store: MidgarOnboardingStore,
        showsSkip: Bool = true
    ) -> some View {
        modifier(MidgarOnboardingModifier(pages: pages, store: store, showsSkip: showsSkip))
    }
}

private struct MidgarOnboardingModifier: ViewModifier {
    let pages: [MidgarOnboardingPage]
    let store: MidgarOnboardingStore
    let showsSkip: Bool

    @State private var isPresented: Bool

    init(pages: [MidgarOnboardingPage], store: MidgarOnboardingStore, showsSkip: Bool) {
        self.pages = pages
        self.store = store
        self.showsSkip = showsSkip
        _isPresented = State(initialValue: store.shouldPresent)
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content.sheet(isPresented: $isPresented) { pager }
        #else
        content.fullScreenCover(isPresented: $isPresented) { pager }
        #endif
    }

    private var pager: some View {
        MidgarOnboarding(pages: pages, store: store, showsSkip: showsSkip) { isPresented = false }
            .interactiveDismissDisabled()
    }
}
