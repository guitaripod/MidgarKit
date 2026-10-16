/// Identifies the MidgarIntelligence module.
public enum MidgarIntelligenceModule {
    public static let name = "MidgarIntelligence"

    /// Whether the SDK this module was built with ships FoundationModels.
    public static var hasFoundationModels: Bool {
        #if canImport(FoundationModels) && !os(tvOS)
        true
        #else
        false
        #endif
    }
}
