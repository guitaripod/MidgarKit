import Foundation

extension MidgarIntelligence {
    /// Streams from the planned route. An on-device infrastructure failure falls back to the cloud only before the first delta, and a stream that ends with no text at all is an `emptyResponse`, not a reason to ask the cloud: after text reached the caller, a second answer would splice two models together, so the failure is thrown.
    func stream(_ prompt: MidgarPrompt, into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        switch try plan(for: prompt) {
        case .cloud:
            try await forward(cloud.streamResponse(to: prompt), into: continuation)
        case .onDevice(let fallback):
            logger("intelligence route=onDevice stream=true")
            var delivered = false
            do {
                for try await delta in onDevice.streamResponse(to: prompt) {
                    delivered = true
                    continuation.yield(delta)
                }
                if !delivered {
                    throw MidgarIntelligenceError.emptyResponse
                }
            } catch {
                try rethrowIfCancelled(error)
                guard !delivered else {
                    let errorType = String(describing: type(of: error))
                    logger("intelligence route=none reason=onDeviceFailedMidStream error=\(errorType)")
                    throw (error as? MidgarIntelligenceError) ?? MidgarIntelligenceError.onDeviceFailed(errorType: errorType)
                }
                try await recover(from: error, fallback: fallback) {
                    try await forward(cloud.streamResponse(to: prompt), into: continuation)
                }
            }
        }
    }

    private func forward(
        _ source: AsyncThrowingStream<String, Error>,
        into continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        for try await delta in source {
            continuation.yield(delta)
        }
    }
}
