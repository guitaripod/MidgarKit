import MidgarCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Identifies the MidgarIntelligence module: on-device and cloud model access lands here.
public enum MidgarIntelligenceModule {
    public static let name = "MidgarIntelligence"

    /// Whether the SDK this module was built with ships FoundationModels.
    public static var hasFoundationModels: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }
}
