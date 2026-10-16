import SwiftUI

/// The onboarding pager: pages of artwork, title and body, page dots and a primary button.
/// The last page's primary button marks the store completed and calls `onFinish`.
public struct MidgarOnboarding: View {
    private let pages: [MidgarOnboardingPage]
    private let store: MidgarOnboardingStore?
    private let showsSkip: Bool
    private let onFinish: @MainActor () -> Void

    @Environment(\.midgarTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: MidgarOnboardingProgress
    @State private var movesForward = true
    @State private var isRunningAction = false

    public init(
        pages: [MidgarOnboardingPage],
        store: MidgarOnboardingStore? = nil,
        showsSkip: Bool = true,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.pages = pages
        self.store = store
        self.showsSkip = showsSkip
        self.onFinish = onFinish
        _progress = State(initialValue: MidgarOnboardingProgress(count: pages.count))
    }

    public var body: some View {
        VStack(spacing: 0) {
            skipBar
            if pages.indices.contains(progress.index) {
                MidgarOnboardingPageView(page: pages[progress.index])
                    .id(progress.index)
                    .transition(reduceMotion ? .opacity : pageTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
            footer
        }
        .background(theme.background.color.ignoresSafeArea())
        .gesture(swipe)
        .animation(reduceMotion ? nil : .snappy, value: progress.index)
        .accessibilityElement(children: .contain)
    }

    private var pageTransition: AnyTransition {
        movesForward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity)
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)).combined(with: .opacity)
    }

    private var skipBar: some View {
        HStack {
            Spacer()
            if showsSkip && !progress.isLast {
                Button(MidgarUIStrings.skip) { finish() }
                    .midgarFont(.body)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, theme.spacing.l)
    }

    private var footer: some View {
        VStack(spacing: theme.spacing.l) {
            pageDots
            primaryButton
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.bottom, theme.spacing.xl)
        .padding(.top, theme.spacing.s)
    }

    private var pageDots: some View {
        HStack(spacing: theme.spacing.s) {
            ForEach(0..<progress.count, id: \.self) { index in
                Circle()
                    .fill(index == progress.index ? theme.accent.color : theme.separator.color)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MidgarUIStrings.pageOf(progress.index + 1, progress.count))
    }

    private var primaryButton: some View {
        Button {
            Task { await tapPrimary() }
        } label: {
            Text(verbatim: primaryTitle)
                .midgarFont(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing.s)
        }
        .midgarProminentButtonStyle()
        .controlSize(.large)
        .disabled(isRunningAction)
    }

    private var primaryTitle: String {
        if pages.indices.contains(progress.index), let custom = pages[progress.index].primaryTitle { return custom }
        return progress.isLast ? MidgarUIStrings.getStarted : MidgarUIStrings.continueButton
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -60 { goForward() }
            if value.translation.width > 60 { goBack() }
        }
    }

    private func tapPrimary() async {
        guard pages.indices.contains(progress.index) else { return finish() }
        isRunningAction = true
        await pages[progress.index].primaryAction?()
        isRunningAction = false
        if progress.isLast { finish() } else { goForward() }
    }

    private func goForward() {
        movesForward = true
        progress.advance()
    }

    private func goBack() {
        movesForward = false
        progress.goBack()
    }

    private func finish() {
        store?.markCompleted()
        onFinish()
    }
}

private struct MidgarOnboardingPageView: View {
    let page: MidgarOnboardingPage

    @Environment(\.midgarTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.xl) {
                artwork
                VStack(spacing: theme.spacing.m) {
                    Text(verbatim: page.title)
                        .midgarFont(.title)
                        .foregroundStyle(theme.label.color)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: page.body)
                        .midgarFont(.body)
                        .foregroundStyle(theme.secondaryLabel.color)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch page.artwork {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 88, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(minHeight: 120)
                .accessibilityHidden(true)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .accessibilityHidden(true)
        case .custom(let view):
            view
        }
    }
}

extension View {
    /// A filled button in the accent: glass-prominent on 26 and later, bordered-prominent before that.
    @ViewBuilder
    fileprivate func midgarProminentButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
