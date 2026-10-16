import SwiftUI

/// The settings screen of a Midgar app: an optional portal card on top, then sections of rows.
/// Put it in a `NavigationStack`; it sets the navigation title itself.
public struct MidgarSettings<PortalCard: View>: View {
    private let title: String
    private let sections: [MidgarSettingsSection]
    private let portalCard: PortalCard

    @Environment(\.midgarTheme) private var theme
    @State private var engine = MidgarSettingsEngine()
    @State private var state = MidgarSettingsEngine.State()

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
                        MidgarSettingsRowView(row: row, isBusy: state.busyRowIDs.contains(row.id), revision: state.revision, engine: engine)
                    }
                } header: {
                    if let title = section.title { Text(verbatim: title) }
                } footer: {
                    if let footer = section.footer { Text(verbatim: footer) }
                }
            }
        }
        .midgarSettingsListStyle()
        .scrollContentBackground(.hidden)
        .background(theme.background.color)
        .navigationTitle(title)
        .midgarToast(toastBinding)
        .alert(pendingTitle, isPresented: pendingBinding) {
            Button(pendingConfirmTitle, role: .destructive) { Task { await engine.confirmPending() } }
            Button(MidgarUIStrings.cancel, role: .cancel) { engine.cancelPending() }
        } message: {
            Text(verbatim: state.pending?.confirmation.message ?? "")
        }
        .alert(MidgarUIStrings.failureTitle, isPresented: failureBinding) {
            Button(MidgarUIStrings.ok, role: .cancel) { engine.dismissFailure() }
        } message: {
            Text(verbatim: state.failureMessage ?? "")
        }
        .onAppear { engine.onChange = { state = $0 } }
    }

    private var pendingTitle: String {
        state.pending?.confirmation.title ?? ""
    }

    private var pendingConfirmTitle: String {
        state.pending?.confirmation.confirmTitle ?? ""
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { state.pending != nil }, set: { if !$0 { engine.cancelPending() } })
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { state.failureMessage != nil }, set: { if !$0 { engine.dismissFailure() } })
    }

    private var toastBinding: Binding<MidgarToast?> {
        Binding(get: { state.toast }, set: { if $0 == nil { engine.dismissToast() } })
    }
}

extension MidgarSettings where PortalCard == EmptyView {
    public init(title: String? = nil, sections: [MidgarSettingsSection]) {
        self.init(title: title, sections: sections) { EmptyView() }
    }
}

extension View {
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
