import Foundation
import MidgarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one entry point for language-model calls. It answers on device when it can and in the cloud otherwise.
///
/// Routing, in order:
/// 1. The `intelligence` kill switch throws ``MidgarIntelligenceError/disabled``.
/// 2. A prompt that needs the cloud (``MidgarModelRequirement/cloudOnly`` or any image) goes to the cloud, or throws ``MidgarIntelligenceError/cloudDisabled`` when `intelligence.cloud` is killed.
/// 3. Otherwise the on-device model answers when it is available. If it fails because the infrastructure failed (the model or its assets became unavailable, or a timeout), the cloud answers instead, unless `intelligence.cloud` is killed. A guardrail or content refusal, an empty or rewritten answer and every other failure are thrown: asking another model the same question would dodge the refusal. Cancellation is never retried.
/// 4. When the on-device model is unavailable the cloud answers, unless `intelligence.cloud` is killed, which throws ``MidgarIntelligenceError/onDeviceUnavailable(_:)``.
///
/// On-device calls are free and unmetered. The cloud meters them: ``MidgarCompletion/creditsCharged`` reports what mako charged. Free cloud grants need an `app_attest` identity (D12), so an `unverified` identity sees ``MidgarIntelligenceError/needsCredits`` until it has paid for credits or a Pass.
public struct MidgarIntelligence: MidgarLanguageModel {
    public static let killSwitch = "intelligence"
    public static let cloudKillSwitch = "intelligence.cloud"

    let onDevice: any MidgarOnDeviceLanguageModel
    let cloud: any MidgarLanguageModel
    private let config: @Sendable () -> MidgarConfig
    let logger: MidgarIntelligenceLogger

    /// - Parameters:
    ///   - onDevice: The on-device model.
    ///   - cloud: The cloud model.
    ///   - config: Read on every call, so a kill switch that arrives while the app runs takes effect on the next call.
    public init(
        onDevice: any MidgarOnDeviceLanguageModel = MidgarOnDeviceModel(),
        cloud: any MidgarLanguageModel,
        config: @escaping @Sendable () -> MidgarConfig = { MidgarConfig() },
        logger: @escaping MidgarIntelligenceLogger = MidgarIntelligenceLogging.standard
    ) {
        self.onDevice = onDevice
        self.cloud = cloud
        self.config = config
        self.logger = logger
    }

    /// The standard wiring: Foundation Models on device, mako through `client`, kill switches from `configStore`.
    public init(client: MidgarHTTPClient, configStore: MidgarConfigStore, cloudModel: String? = nil) {
        self.init(
            cloud: MidgarCloudModel(client: client, model: cloudModel),
            config: { configStore.current }
        )
    }

    /// Whether the on-device model can answer now.
    public var onDeviceAvailability: MidgarOnDeviceAvailability {
        onDevice.availability
    }

    public func respond(to prompt: MidgarPrompt) async throws -> MidgarCompletion {
        let plan = try plan(for: prompt)
        switch plan {
        case .cloud:
            return try await cloud.respond(to: prompt)
        case .onDevice(let fallback):
            do {
                logger("intelligence route=onDevice")
                return try await onDevice.respond(to: prompt)
            } catch {
                try rethrowIfCancelled(error)
                return try await recover(from: error, fallback: fallback) {
                    try await cloud.respond(to: prompt)
                }
            }
        }
    }

    public func streamResponse(to prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(prompt, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum Plan {
        case cloud
        case onDevice(cloudFallback: Bool)
    }

    func plan(for prompt: MidgarPrompt) throws -> Plan {
        let snapshot = config()
        if snapshot.isKilled(Self.killSwitch) {
            logger("intelligence route=none reason=killed")
            throw MidgarIntelligenceError.disabled
        }
        let cloudAllowed = !snapshot.isKilled(Self.cloudKillSwitch)
        if prompt.effectiveRequirement == .cloudOnly {
            guard cloudAllowed else {
                logger("intelligence route=none reason=cloudKilled")
                throw MidgarIntelligenceError.cloudDisabled
            }
            logger("intelligence route=cloud reason=requirement")
            return .cloud
        }
        switch onDevice.availability {
        case .available:
            return .onDevice(cloudFallback: cloudAllowed)
        case .unavailable(let reason):
            guard cloudAllowed else {
                logger("intelligence route=none reason=cloudKilled onDevice=\(reason)")
                throw MidgarIntelligenceError.onDeviceUnavailable(reason)
            }
            logger("intelligence route=cloud reason=onDeviceUnavailable onDevice=\(reason)")
            return .cloud
        }
    }

    /// Runs `cloudAttempt` after an on-device failure when the failure is infrastructure and the cloud may answer, and throws the failure otherwise.
    func recover<Result>(
        from error: any Error,
        fallback: Bool,
        cloudAttempt: () async throws -> Result
    ) async throws -> Result {
        let errorType = String(describing: type(of: error))
        guard fallback, isInfrastructureFailure(error) else {
            logger("intelligence route=none reason=onDeviceFailed error=\(errorType) fallback=\(fallback ? "refused" : "killed")")
            throw (error as? MidgarIntelligenceError) ?? MidgarIntelligenceError.onDeviceFailed(errorType: errorType)
        }
        logger("intelligence route=cloud reason=onDeviceFailed error=\(errorType)")
        return try await cloudAttempt()
    }

    /// True for failures where the cloud may stand in for the device: the model or its assets are unavailable, or the call timed out. A refusal, an empty or rewritten answer or any other failure says something about the prompt or the answer, not about the device.
    func isInfrastructureFailure(_ error: any Error) -> Bool {
        if case MidgarIntelligenceError.onDeviceUnavailable = error {
            return true
        }
        return (error as? URLError)?.code == .timedOut
    }

    /// Rethrows when the failure is the caller cancelling, which must never fall back to the cloud.
    func rethrowIfCancelled(_ error: any Error) throws {
        if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
            throw error is CancellationError ? error : CancellationError()
        }
    }
}
