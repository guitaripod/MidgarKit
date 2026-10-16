/// Why the on-device model cannot answer right now.
public enum MidgarOnDeviceUnavailableReason: Sendable, Equatable {
    /// This platform or SDK has no Foundation Models, for example Linux or tvOS.
    case platformUnsupported
    /// The operating system is older than the first release with Foundation Models.
    case operatingSystemTooOld
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

/// Whether the on-device model can answer a prompt now.
public enum MidgarOnDeviceAvailability: Sendable, Equatable {
    case available
    case unavailable(MidgarOnDeviceUnavailableReason)
}

/// Anything that answers a ``MidgarPrompt``: the on-device model, the cloud model, or the router over both.
public protocol MidgarLanguageModel: Sendable {
    func respond(to prompt: MidgarPrompt) async throws -> MidgarCompletion

    /// Text deltas in order. Concatenated they equal the full answer. A model that cannot stream yields the whole answer as one delta.
    func streamResponse(to prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error>
}

/// A ``MidgarLanguageModel`` that runs on the device and can report whether it is ready.
public protocol MidgarOnDeviceLanguageModel: MidgarLanguageModel {
    var availability: MidgarOnDeviceAvailability { get }
}
