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
        self.init(pages: pages, store: store, showsSkip: showsSkip, startingAt: 0, onFinish: onFinish)
    }

    init(
        pages: [MidgarOnboardingPage],
        store: MidgarOnboardingStore?,
        showsSkip: Bool,
        startingAt index: Int,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.pages = pages
        self.store = store
        self.showsSkip = showsSkip
        self.onFinish = onFinish
        _progress = State(initialValue: MidgarOnboardingProgress(count: pages.count, index: index))
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
        .midgarSwipeNavigation(forward: goForward, back: goBack, isEnabled: !isRunningAction)
        .animation(reduceMotion ? nil : .snappy, value: progress.index)
        .accessibilityElement(children: .contain)
    }

    private var pageTransition: AnyTransition {
        movesForward
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity)
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)).combined(with: .opacity)
    }

    /// Back on the leading side and Skip on the trailing side. Back is a real control, so VoiceOver, Switch Control and keyboards can leave a page without the swipe. Both wait while a page's primary action runs: a Skip then would finish the onboarding, and the action's own finish after it would call `onFinish` a second time.
    private var skipBar: some View {
        HStack {
            if !progress.isFirst {
                Button(MidgarUIStrings.back) { goBack() }
                    .midgarFont(.body)
                    .disabled(isRunningAction)
            }
            Spacer()
            if showsSkip && !progress.isLast {
                Button(MidgarUIStrings.skip) { finish() }
                    .midgarFont(.body)
                    .disabled(isRunningAction)
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

    private func tapPrimary() async {
        guard !isRunningAction else { return }
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
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 88
    @ScaledMetric(relativeTo: .largeTitle) private var symbolHeight: CGFloat = 120
    @ScaledMetric(relativeTo: .largeTitle) private var imageHeight: CGFloat = 280

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
                .font(.system(size: symbolSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.accent.color)
                .frame(minHeight: symbolHeight)
                .accessibilityHidden(true)
        case .image(let image):
            image
                .resizable()
                .scaledToFit()
                .frame(maxHeight: imageHeight)
                .accessibilityHidden(true)
        case .custom(let view):
            view
        }
    }
}

extension View {
    /// Moves between pages with a horizontal swipe, where the platform has drag gestures. tvOS has none and moves with the focus engine and the Back button.
    @ViewBuilder
    fileprivate func midgarSwipeNavigation(forward: @escaping () -> Void, back: @escaping () -> Void, isEnabled: Bool) -> some View {
        #if os(tvOS)
        self
        #else
        gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard isEnabled else { return }
                if value.translation.width < -60 { forward() }
                if value.translation.width > 60 { back() }
            }
        )
        #endif
    }
}
