import Foundation
import MidgarCore

/// What the caller can still spend in the cloud, as mako reports it.
public struct MidgarCreditBalance: Sendable, Equatable {
    /// One weekly free bucket, keyed by alias in ``weekly``.
    public struct WeeklyBucket: Sendable, Equatable {
        public let limit: Int
        public let remaining: Int
        public let resetsAt: Date?

        public init(limit: Int, remaining: Int, resetsAt: Date?) {
            self.limit = limit
            self.remaining = remaining
            self.resetsAt = resetsAt
        }
    }

    public let credits: Int
    public let weekly: [String: WeeklyBucket]

    public init(credits: Int, weekly: [String: WeeklyBucket] = [:]) {
        self.credits = credits
        self.weekly = weekly
    }
}

/// Calls mako through the gateway: `POST /v1/intelligence/v1/run/chat.completion`, which the gateway forwards to mako's `POST /v1/run/chat.completion`.
///
/// mako answers the whole completion in one response, so ``streamResponse(to:)`` yields it as a single delta. A POST is never retried, so a slow answer cannot be charged twice.
public struct MidgarCloudModel: MidgarLanguageModel {
    static let service = "intelligence"
    static let chatPath = "v1/run/chat.completion"
    static let balancePath = "v1/credits/balance"

    private let client: MidgarHTTPClient
    private let model: String?
    private let logger: MidgarIntelligenceLogger

    /// - Parameters:
    ///   - client: The app's gateway client. Its token provider supplies the Midgar ID session.
    ///   - model: A mako model id to pin. Nil lets mako use the app's default chat model.
    public init(
        client: MidgarHTTPClient,
        model: String? = nil,
        logger: @escaping MidgarIntelligenceLogger = MidgarIntelligenceLogging.standard
    ) {
        self.client = client
        self.model = model
        self.logger = logger
    }

    public func respond(to prompt: MidgarPrompt) async throws -> MidgarCompletion {
        let request = MidgarRequest(
            service: Self.service,
            path: Self.chatPath,
            method: .post,
            body: MidgarChatRequestWire(prompt: prompt, model: model)
        )
        let reply: MidgarChatResponseWire
        do {
            reply = try await client.send(request)
        } catch {
            throw mapped(error)
        }
        guard !reply.content.isEmpty else {
            logger("intelligence cloud outcome=empty")
            throw MidgarIntelligenceError.emptyResponse
        }
        logger("intelligence cloud outcome=ok model=\(reply.model) credits=\(reply.creditsCharged)")
        return MidgarCompletion(
            text: reply.content,
            route: .cloud,
            model: reply.model,
            creditsCharged: reply.creditsCharged
        )
    }

    public func streamResponse(to prompt: MidgarPrompt) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let completion = try await respond(to: prompt)
                    continuation.yield(completion.text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Reads the caller's credit balance and weekly free buckets from `GET /v1/credits/balance`.
    ///
    /// TODO(P3.07): mako's balance is per app today. When the wallet per Midgar ID and the Pass allowance get an endpoint, read the allowance from it here.
    public func balance() async throws -> MidgarCreditBalance {
        let request = MidgarRequest(service: Self.service, path: Self.balancePath)
        let wire: MidgarBalanceWire
        do {
            wire = try await client.send(request)
        } catch {
            throw mapped(error)
        }
        return MidgarCreditBalance(
            credits: wire.balance,
            weekly: (wire.weekly ?? [:]).mapValues {
                MidgarCreditBalance.WeeklyBucket(limit: $0.limit, remaining: $0.remaining, resetsAt: Self.date($0.resetsAt))
            }
        )
    }

    /// Maps a gateway failure to this module's typed errors. Cancellation becomes `CancellationError`.
    private func mapped(_ error: any Error) -> any Error {
        guard let http = error as? MidgarHTTPError else {
            return error
        }
        switch http {
        case .paymentRequired:
            return MidgarIntelligenceError.needsCredits
        case .rateLimited(let retryAfter):
            return MidgarIntelligenceError.rateLimited(retryAfter: retryAfter)
        case .cancelled:
            return CancellationError()
        default:
            return MidgarIntelligenceError.cloudFailed(http)
        }
    }

    private static func date(_ text: String?) -> Date? {
        guard let text else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
