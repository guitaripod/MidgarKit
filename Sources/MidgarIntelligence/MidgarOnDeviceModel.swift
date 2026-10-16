import Foundation
#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// Apple's on-device model (`SystemLanguageModel.default`) behind ``MidgarLanguageModel``.
///
/// Where Foundation Models does not exist, ``availability`` reports `.unavailable(.platformUnsupported)` and every call throws ``MidgarIntelligenceError/onDeviceUnavailable(_:)``. Each call uses a fresh session, so calls share no conversation state.
public struct MidgarOnDeviceModel: MidgarOnDeviceLanguageModel {
    public init() {}

    public var availability: MidgarOnDeviceAvailability {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return FoundationModelsBackend.availability()
        }
        return .unavailable(.operatingSystemTooOld)
        #else
        return .unavailable(.platformUnsupported)
        #endif
    }

    public func respond(to prompt: MidgarPrompt) async throws -> MidgarCompletion {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            try requireAvailable()
            let text = try await FoundationModelsBackend.respond(to: prompt)
            guard !text.isEmpty else {
                throw MidgarIntelligenceError.emptyResponse
            }
            return MidgarCompletion(text: text, route: .onDevice)
        }
        #endif
        throw MidgarIntelligenceError.onDeviceUnavailable(unavailableReason)
    }

    public func streamResponse(to prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await pump(prompt, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Forwards the backend's deltas to the stream.
    private func pump(_ prompt: MidgarPrompt, into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            try requireAvailable()
            for try await delta in FoundationModelsBackend.deltas(for: prompt) {
                continuation.yield(delta)
            }
            return
        }
        #endif
        throw MidgarIntelligenceError.onDeviceUnavailable(unavailableReason)
    }

    /// Throws ``MidgarIntelligenceError/onDeviceUnavailable(_:)`` unless the model is ready.
    private func requireAvailable() throws {
        if case .unavailable(let reason) = availability {
            throw MidgarIntelligenceError.onDeviceUnavailable(reason)
        }
    }

    private var unavailableReason: MidgarOnDeviceUnavailableReason {
        if case .unavailable(let reason) = availability {
            return reason
        }
        return .unknown
    }
}

#if canImport(FoundationModels) && !os(tvOS)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
enum FoundationModelsBackend {
    static func availability() -> MidgarOnDeviceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(mapped(reason))
        @unknown default:
            return .unavailable(.unknown)
        }
    }

    static func respond(to prompt: MidgarPrompt) async throws -> String {
        let session = LanguageModelSession(model: .default, instructions: prompt.instructions)
        let response = try await session.respond(to: prompt.text, options: options(for: prompt))
        return response.content
    }

    /// Foundation Models streams cumulative snapshots; this turns them into the new text of each step.
    static func deltas(for prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(model: .default, instructions: prompt.instructions)
                    var emitted = ""
                    for try await snapshot in session.streamResponse(to: prompt.text, options: options(for: prompt)) {
                        let full: String = snapshot.content
                        if let delta = delta(from: emitted, to: full) {
                            continuation.yield(delta)
                            emitted = full
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The text `full` adds to `emitted`, or nil when nothing was added or the model rewrote earlier text.
    static func delta(from emitted: String, to full: String) -> String? {
        guard full.count > emitted.count, full.hasPrefix(emitted) else {
            return nil
        }
        return String(full.dropFirst(emitted.count))
    }

    private static func options(for prompt: MidgarPrompt) -> GenerationOptions {
        GenerationOptions(temperature: prompt.temperature, maximumResponseTokens: prompt.maxOutputTokens)
    }

    private static func mapped(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> MidgarOnDeviceUnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            return .unknown
        }
    }
}
#endif
