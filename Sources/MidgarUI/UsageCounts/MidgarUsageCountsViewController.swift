import SwiftUI
import MidgarCore

#if canImport(UIKit)
import UIKit

/// The Usage Counts screen for UIKit apps: a view controller that hosts ``MidgarUsageCounts``. Push it on a navigation controller from the row ``MidgarSettingsRow/usageCountsDetail(perform:)``; it sets its own title. On macOS the same name is an `NSHostingController` around the same screen.
@MainActor
public final class MidgarUsageCountsViewController: UIHostingController<AnyView> {
    /// - Parameters:
    ///   - appID: The app's registry slug. Defaults to the one the app configured ``MidgarSignals`` with.
    ///   - theme: The look of the screen. Defaults to the theme installed with `MidgarTheme.install(_:)`.
    public convenience init(appID: String? = nil, theme: MidgarTheme = .current) {
        self.init(model: MidgarUsageCountsModel(appID: appID ?? MidgarSignals.appID), theme: theme)
    }

    init(model: MidgarUsageCountsModel, theme: MidgarTheme = .current) {
        super.init(rootView: AnyView(MidgarUsageCounts(model: model).midgarTheme(theme)))
        title = MidgarUIStrings.usageCountsTitle
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#elseif canImport(AppKit)
import AppKit

/// The Usage Counts screen for AppKit apps: a view controller that hosts ``MidgarUsageCounts``. Show it in a window or a sheet from the row ``MidgarSettingsRow/usageCountsDetail(perform:)``; it sets its own title. On the UIKit platforms the same name is a `UIHostingController` around the same screen.
@MainActor
public final class MidgarUsageCountsViewController: NSHostingController<AnyView> {
    /// - Parameters:
    ///   - appID: The app's registry slug. Defaults to the one the app configured ``MidgarSignals`` with.
    ///   - theme: The look of the screen. Defaults to the theme installed with `MidgarTheme.install(_:)`.
    public convenience init(appID: String? = nil, theme: MidgarTheme = .current) {
        self.init(model: MidgarUsageCountsModel(appID: appID ?? MidgarSignals.appID), theme: theme)
    }

    init(model: MidgarUsageCountsModel, theme: MidgarTheme = .current) {
        super.init(rootView: AnyView(MidgarUsageCounts(model: model).midgarTheme(theme)))
        title = MidgarUIStrings.usageCountsTitle
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#endif
