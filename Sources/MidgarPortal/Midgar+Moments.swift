import Foundation

extension Midgar {
    /// Offers a related Midgar app at a moment the host app names, with the App Store's own overlay.
    ///
    /// Call it where the app has just shown the person something the other app is good at, such as after an export. Which app is offered comes from the registry: the host's `[portal.moments]` table maps the moment's name to a related app. Nothing shows when
    /// - the host has no such moment in the registry,
    /// - the person already has the app (a Midgar ID session in it, from ``MidgarConfig/account``, or it is installed on this device),
    /// - this moment offered an app in the last 14 days (the cap is kept per app),
    /// - the config has a parental ``MidgarConfig/gate``, or
    /// - the platform is macOS or tvOS, which have no overlay.
    ///
    /// The offer is reported as an `overlay` signal for the offered app with the placement `feature`, and the install is credited to the campaign token `<host>-feature`. The call returns at once; the work happens in the background.
    @MainActor
    public static func moment(_ name: String, config: MidgarConfig = .default) {
        #if (os(iOS) || os(visionOS)) && !targetEnvironment(macCatalyst)
        var momentConfig = config
        momentConfig.placement = PortalMoments.placement
        Task { @MainActor in
            _ = await MomentCoordinator.run(
                moment: name,
                config: momentConfig,
                dependencies: .live(config: momentConfig),
                telemetry: Telemetry(config: momentConfig)
            )
        }
        #endif
    }
}
