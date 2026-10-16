import SwiftUI

/// One change worth telling people about.
public struct MidgarWhatsNewItem: Identifiable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var body: String
    public var systemImage: String

    public init(id: String? = nil, title: String, body: String, systemImage: String) {
        self.id = id ?? title
        self.title = title
        self.body = body
        self.systemImage = systemImage
    }
}

/// The What's New sheet: a title, the list of changes and a Continue button.
public struct MidgarWhatsNew: View {
    private let items: [MidgarWhatsNewItem]
    private let title: String
    private let onContinue: @MainActor () -> Void

    @Environment(\.midgarTheme) private var theme

    public init(items: [MidgarWhatsNewItem], title: String? = nil, onContinue: @escaping @MainActor () -> Void) {
        self.items = items
        self.title = title ?? MidgarUIStrings.whatsNew
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xl) {
                    Text(verbatim: title)
                        .midgarFont(.largeTitle)
                        .foregroundStyle(theme.label.color)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.xxl)
                .padding(.bottom, theme.spacing.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            Button(action: onContinue) {
                Text(verbatim: MidgarUIStrings.continueButton)
                    .midgarFont(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.s)
            }
            .midgarWhatsNewButtonStyle()
            .controlSize(.large)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.xl)
        }
        .background(theme.background.color.ignoresSafeArea())
    }

    private func itemRow(_ item: MidgarWhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.l) {
            Image(systemName: item.systemImage)
                .font(.title)
                .foregroundStyle(theme.accent.color)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(verbatim: item.title)
                    .midgarFont(.headline)
                    .foregroundStyle(theme.label.color)
                Text(verbatim: item.body)
                    .midgarFont(.subheadline)
                    .foregroundStyle(theme.secondaryLabel.color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    @ViewBuilder
    fileprivate func midgarWhatsNewButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// Shows the What's New sheet once per app version, when `store` says it is due, and records the version when it closes.
    public func midgarWhatsNew(
        items: [MidgarWhatsNewItem],
        version: String,
        store: MidgarWhatsNewStore,
        showOnFirstInstall: Bool = false
    ) -> some View {
        modifier(
            MidgarWhatsNewModifier(items: items, version: version, store: store, showOnFirstInstall: showOnFirstInstall)
        )
    }
}

private struct MidgarWhatsNewModifier: ViewModifier {
    let items: [MidgarWhatsNewItem]
    let version: String
    let store: MidgarWhatsNewStore
    let showOnFirstInstall: Bool

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task { evaluate() }
            .sheet(isPresented: $isPresented) {
                MidgarWhatsNew(items: items) { isPresented = false }
                    .interactiveDismissDisabled()
                    .onDisappear { store.markShown(version) }
            }
    }

    /// Opens the sheet when it is due and there is something to show; otherwise keeps the stored version current.
    private func evaluate() {
        guard !items.isEmpty, store.shouldShow(for: version, showOnFirstInstall: showOnFirstInstall) else {
            store.recordInstallIfNeeded(version: version)
            return
        }
        isPresented = true
    }
}

#if canImport(UIKit)
import UIKit

/// What's New as a UIKit controller. `presentIfNeeded` shows it only when the store says it is due.
@MainActor
public final class MidgarWhatsNewViewController: UIHostingController<AnyView> {
    private let store: MidgarWhatsNewStore
    private let version: String

    public init(
        items: [MidgarWhatsNewItem],
        version: String,
        store: MidgarWhatsNewStore,
        theme: MidgarTheme = .current,
        onContinue: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.version = version
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(
            MidgarWhatsNew(items: items) { [weak self] in
                self?.dismiss(animated: true)
                onContinue()
            }
            .midgarTheme(theme)
        )
        isModalInPresentation = true
        #if !os(tvOS)
        modalPresentationStyle = .pageSheet
        #endif
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { store.markShown(version) }
    }

    /// Presents the sheet from `presenter` when it is due, and returns whether it was presented.
    @discardableResult
    public static func presentIfNeeded(
        items: [MidgarWhatsNewItem],
        version: String,
        store: MidgarWhatsNewStore,
        showOnFirstInstall: Bool = false,
        theme: MidgarTheme = .current,
        from presenter: UIViewController
    ) -> Bool {
        guard !items.isEmpty, store.shouldShow(for: version, showOnFirstInstall: showOnFirstInstall) else {
            store.recordInstallIfNeeded(version: version)
            return false
        }
        let controller = MidgarWhatsNewViewController(items: items, version: version, store: store, theme: theme)
        presenter.present(controller, animated: true)
        return true
    }
}
#endif
