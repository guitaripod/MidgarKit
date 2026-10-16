import SwiftUI

/// The settings screen of a Midgar app: an optional portal card on top, then sections of rows.
/// Put it in a `NavigationStack`; it sets the navigation title itself.
public struct MidgarSettings<PortalCard: View>: View {
    private let title: String
    private let sections: [MidgarSettingsSection]
    private let portalCard: PortalCard

    @Environment(\.midgarTheme) private var theme
    @StateObject private var model = MidgarSettingsModel()

    public init(
        title: String? = nil,
        sections: [MidgarSettingsSection],
        @ViewBuilder portalCard: () -> PortalCard
    ) {
        self.title = title ?? MidgarUIStrings.settings
        self.sections = sections
        self.portalCard = portalCard()
    }

    public var body: some View {
        List {
            if PortalCard.self != EmptyView.self {
                Section {
                    portalCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        MidgarSettingsRowView(
                            row: row,
                            isBusy: model.state.busyRowIDs.contains(row.id),
                            revision: model.state.revision,
                            engine: model.engine
                        )
                    }
                } header: {
                    if let title = section.title { Text(verbatim: title) }
                } footer: {
                    if let footer = section.footer { Text(verbatim: footer) }
                }
            }
        }
        .midgarSettingsListStyle()
        .midgarHidingListBackground()
        .background(theme.background.color)
        .navigationTitle(title)
        .midgarToast(toastBinding)
        .alert(pendingTitle, isPresented: pendingBinding) {
            Button(pendingConfirmTitle, role: .destructive) { model.engine.beginConfirmedAction() }
            Button(MidgarUIStrings.cancel, role: .cancel) { model.engine.cancelPending() }
        } message: {
            Text(verbatim: model.state.pending?.confirmation.message ?? "")
        }
        .alert(MidgarUIStrings.failureTitle, isPresented: failureBinding) {
            Button(MidgarUIStrings.ok, role: .cancel) { model.engine.dismissFailure() }
        } message: {
            Text(verbatim: model.state.failureMessage ?? "")
        }
    }

    private var pendingTitle: String {
        model.state.pending?.confirmation.title ?? ""
    }

    private var pendingConfirmTitle: String {
        model.state.pending?.confirmation.confirmTitle ?? ""
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { model.state.pending != nil }, set: { if !$0 { model.engine.cancelPending() } })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { model.state.failureMessage != nil }, set: { if !$0 { model.engine.dismissFailure() } })
    }

    private var toastBinding: Binding<MidgarToast?> {
        Binding(get: { model.state.toast }, set: { if $0 == nil { model.engine.dismissToast() } })
    }
}

/// Owns the engine for a SwiftUI settings screen and republishes its state. The engine reports to the model through a weak reference, so the two never keep each other alive; the package targets iOS 16, which predates `@Observable`.
@MainActor
final class MidgarSettingsModel: ObservableObject {
    let engine: MidgarSettingsEngine
    @Published private(set) var state: MidgarSettingsEngine.State

    init(engine: MidgarSettingsEngine = MidgarSettingsEngine()) {
        self.engine = engine
        self.state = engine.state
        engine.onChange = { [weak self] state in self?.state = state }
    }
}

extension MidgarSettings where PortalCard == EmptyView {
    public init(title: String? = nil, sections: [MidgarSettingsSection]) {
        self.init(title: title, sections: sections) { EmptyView() }
    }
}

extension View {
    /// Lets the screen's own background show through the list, where the platform allows it.
    @ViewBuilder
    fileprivate func midgarHidingListBackground() -> some View {
        #if os(tvOS)
        self
        #else
        scrollContentBackground(.hidden)
        #endif
    }

    /// Inset grouped lists where the platform has them, the closest list style elsewhere.
    @ViewBuilder
    fileprivate func midgarSettingsListStyle() -> some View {
        #if os(iOS) || os(visionOS)
        listStyle(.insetGrouped)
        #elseif os(macOS)
        listStyle(.inset)
        #else
        listStyle(.grouped)
        #endif
    }
}
