import Foundation
import MidgarCore

/// What the portal knows about the person across Midgar apps. A field is `nil` when its call failed, so a missing Midgar ID, no network and a refusal all read as "unknown" rather than "none".
struct PortalAccountSnapshot: Sendable, Equatable {
    var appSlugs: [String]?
    var entitlements: [PortalEntitlement]?

    /// `true` when neither call answered.
    var isUnknown: Bool { appSlugs == nil && entitlements == nil }

    /// `true` when both calls answered.
    var isComplete: Bool { appSlugs != nil && entitlements != nil }
}

/// Reads the account through a ``PortalAccountSource`` and keeps the answer for a few minutes, so opening the portal and calling ``Midgar/moment(_:config:)`` several times in a session cost one round trip. Only an answer to both calls is cached, and an earlier good answer is not served after a failure, so going offline reads as unknown.
actor PortalAccount {
    static let timeToLive: TimeInterval = 10 * 60

    private let source: any PortalAccountSource
    private let now: @Sendable () -> Date
    private var cached: (snapshot: PortalAccountSnapshot, at: Date)?
    private var inFlight: Task<PortalAccountSnapshot, Never>?

    init(source: any PortalAccountSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.now = now
    }

    /// The cached answer while it is fresh, else a fresh read shared by every caller that arrives while it runs.
    func snapshot() async -> PortalAccountSnapshot {
        if let cached, now().timeIntervalSince(cached.at) < Self.timeToLive {
            return cached.snapshot
        }
        if let inFlight {
            return await inFlight.value
        }
        let source = source
        let task = Task { await Self.read(source) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        cached = snapshot.isComplete ? (snapshot, now()) : nil
        return snapshot
    }

    /// Forgets the cached answer, for the portal opening after a purchase.
    func invalidate() {
        cached = nil
    }

    private static func read(_ source: any PortalAccountSource) async -> PortalAccountSnapshot {
        async let slugs = try? await source.appSlugs()
        async let entitlements = try? await source.entitlements()
        return await PortalAccountSnapshot(appSlugs: slugs, entitlements: entitlements)
    }
}

/// One shared ``PortalAccount`` per HTTP client, so the portal and the moments of an app share the cache.
@MainActor
enum PortalAccountDirectory {
    private static var accounts: [ObjectIdentifier: (client: MidgarHTTPClient, account: PortalAccount)] = [:]

    static func account(for client: MidgarHTTPClient) -> PortalAccount {
        let key = ObjectIdentifier(client)
        if let existing = accounts[key] { return existing.account }
        let created = PortalAccount(source: LivePortalAccountSource(http: client))
        accounts[key] = (client, created)
        return created
    }
}
