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
            let text: String
            do {
                text = try await FoundationModelsBackend.respond(to: prompt)
            } catch {
                throw FoundationModelsBackend.mapped(error)
            }
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
            var delivered = false
            for try await delta in FoundationModelsBackend.deltas(for: prompt) {
                delivered = true
                continuation.yield(delta)
            }
            guard delivered else {
                throw MidgarIntelligenceError.emptyResponse
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

/// Turns the cumulative snapshots of a Foundation Models stream into the new text of each step. A snapshot that does not extend what was already delivered means the model rewrote earlier text; that throws ``MidgarIntelligenceError/onDeviceOutputRewritten`` instead of silently dropping the rest of the answer.
struct OnDeviceSnapshotAccumulator: Sendable {
    private(set) var emitted = ""

    /// The text `full` adds, or nil when it adds nothing.
    mutating func delta(for full: String) throws -> String? {
        guard full != emitted else {
            return nil
        }
        guard full.hasPrefix(emitted) else {
            throw MidgarIntelligenceError.onDeviceOutputRewritten
        }
        let added = String(full.dropFirst(emitted.count))
        emitted = full
        return added
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
                    var accumulator = OnDeviceSnapshotAccumulator()
                    for try await snapshot in session.streamResponse(to: prompt.text, options: options(for: prompt)) {
                        let full: String = snapshot.content
                        if let delta = try accumulator.delta(for: full) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turns a Foundation Models failure into the module's typed errors where the router must tell them apart: missing assets are an outage, a guardrail or a refusal is an answer. Anything else passes through and is reported by type name.
    static func mapped(_ error: any Error) -> any Error {
        guard let failure = error as? LanguageModelSession.GenerationError else {
            return error
        }
        switch failure {
        case .assetsUnavailable:
            return MidgarIntelligenceError.onDeviceUnavailable(.modelNotReady)
        case .guardrailViolation, .refusal:
            return MidgarIntelligenceError.onDeviceRefused
        default:
            return error
        }
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
