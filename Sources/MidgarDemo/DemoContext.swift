import Foundation

/// What a demo world may assume about this launch. The flags default to the demo-mode values, so a world
/// that reads them never has to ask whether it is running in a screenshot run.
public struct DemoContext: Sendable, Equatable {
    /// The frozen "now" every date-driven screen should use. Read it through `DemoClock.now`.
    public let date: Date
    public let locale: Locale
    public let skipOnboarding: Bool
    public let hidePaywall: Bool
    public let suppressReviewPrompts: Bool
    public let suppressNetwork: Bool

    public init(
        date: Date,
        locale: Locale,
        skipOnboarding: Bool = true,
        hidePaywall: Bool = true,
        suppressReviewPrompts: Bool = true,
        suppressNetwork: Bool = true
    ) {
        self.date = date
        self.locale = locale
        self.skipOnboarding = skipOnboarding
        self.hidePaywall = hidePaywall
        self.suppressReviewPrompts = suppressReviewPrompts
        self.suppressNetwork = suppressNetwork
    }
}
