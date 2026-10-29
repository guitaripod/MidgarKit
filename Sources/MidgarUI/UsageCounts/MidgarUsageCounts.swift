import SwiftUI
import MidgarCore

/// The Usage Counts screen of a Midgar app's Settings: what usage counts are, the switch that turns them off (the same as ``MidgarSettingsRow/usageCounts()``), every count this app may send and why, this app's own public numbers, and a link to all of Midgar's numbers.
///
/// The numbers section appears only when the latest finished week could be read from the public numbers (`https://api.midgarcorp.cc/v1/ops/public/stats`). That one request carries no identifier and is not repeated; when it fails the section is simply not there. The app is found from the slug it configured ``MidgarSignals`` with.
///
/// Put it in a `NavigationStack`; it sets the navigation title itself. UIKit apps use ``MidgarUsageCountsViewController`` on the platforms that have UIKit. Open it from the row ``MidgarSettingsRow/usageCountsDetail(perform:)``.
public struct MidgarUsageCounts: View {
    @Environment(\.midgarTheme) private var theme
    @StateObject private var model: MidgarUsageCountsModel

    /// - Parameter appID: The app's registry slug, such as `solar-beam`. Defaults to the one the app configured ``MidgarSignals`` with; pass it only when signals are configured later.
    public init(appID: String? = nil) {
        _model = StateObject(wrappedValue: MidgarUsageCountsModel(appID: appID ?? MidgarSignals.appID))
    }

    init(model: MidgarUsageCountsModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        MidgarSettings(title: MidgarUIStrings.usageCountsTitle, sections: model.sections) { intro }
            .task { await model.load() }
    }

    private var intro: some View {
        Text(verbatim: MidgarUIStrings.usageCountsIntro)
            .midgarFont(.subheadline)
            .foregroundStyle(theme.secondaryLabel.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.l)
            .padding(.vertical, theme.spacing.s)
    }
}
