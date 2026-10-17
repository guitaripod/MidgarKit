import Foundation
import MidgarCore
@testable import MidgarPortal

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers the portal's two account calls from canned results and counts them.
final class FakeAccountSource: PortalAccountSource, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var slugCalls = 0
    private var entitlementCalls = 0
    var slugs: Result<[String], any Error>
    var entitlements: Result<[PortalEntitlement], any Error>

    init(
        slugs: Result<[String], any Error> = .success([]),
        entitlements: Result<[PortalEntitlement], any Error> = .success([])
    ) {
        self.slugs = slugs
        self.entitlements = entitlements
    }

    var calls: (slugs: Int, entitlements: Int) {
        lock.withLock { (slugCalls, entitlementCalls) }
    }

    func appSlugs() async throws -> [String] {
        let result = lock.withLock { () -> Result<[String], any Error> in
            slugCalls += 1
            return slugs
        }
        return try result.get()
    }

    func entitlements() async throws -> [PortalEntitlement] {
        let result = lock.withLock { () -> Result<[PortalEntitlement], any Error> in
            entitlementCalls += 1
            return entitlements
        }
        return try result.get()
    }
}

/// A clock a test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

@MainActor
final class FakePresenter: MomentPresenting {
    struct Shown: Equatable {
        let appId: String
        let campaignToken: String
        let providerToken: String?
    }

    var shown: [Shown] = []
    var succeeds = true

    func present(_ app: MidgarApp, campaignToken: String, providerToken: String?) -> Bool {
        guard succeeds else { return false }
        shown.append(Shown(appId: app.appId, campaignToken: campaignToken, providerToken: providerToken))
        return true
    }
}

enum PortalFixtures {
    /// A moment in January 2027, far from any real catalog date.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func app(
        _ slug: String,
        bundle: String? = nil,
        id: String? = nil,
        platforms: [MidgarPlatform] = [.ios],
        moments: [String: String] = [:],
        accent: String = "#4466CC",
        tagline: String? = nil
    ) -> MidgarApp {
        MidgarApp(
            appId: id ?? "id-\(slug)",
            bundleId: bundle ?? "com.example.\(slug)",
            name: slug.capitalized,
            tagline: tagline ?? "\(slug.capitalized) tagline.",
            genre: "Music",
            accentHex: accent,
            platforms: platforms,
            slug: slug,
            moments: moments
        )
    }

    static func lifetime(_ app: String, _ name: String? = "pro") -> PortalEntitlement {
        PortalEntitlement(app: app, entitlement: name, kind: "non_consumable")
    }

    static func subscription(_ app: String, _ name: String? = "pro", endsAfter seconds: TimeInterval, grace: Bool = false) -> PortalEntitlement {
        let end = (now.timeIntervalSince1970 + seconds) * 1000
        return PortalEntitlement(
            app: app,
            entitlement: name,
            kind: "subscription",
            expiresDate: grace ? end - 86_400_000 : end,
            graceExpiresDate: grace ? end : nil,
            inGracePeriod: grace
        )
    }

    static func defaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let name = "midgar-portal-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }
}

/// Serves canned bodies for the portal's account host and records the requests it saw.
final class PortalHTTPStub: URLProtocol, @unchecked Sendable {
    struct Seen: Equatable {
        let path: String
        let authorization: String?
        let appID: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [Seen] = []
    nonisolated(unsafe) private static var bodies: [String: (status: Int, body: String)] = [:]

    static func reset(_ bodies: [String: (status: Int, body: String)]) {
        lock.withLock {
            seen = []
            self.bodies = bodies
        }
    }

    static var requests: [Seen] { lock.withLock { seen } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortalHTTPStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "portal-account.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let answer = Self.lock.withLock { () -> (status: Int, body: String) in
            Self.seen.append(Seen(
                path: url.path,
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                appID: request.value(forHTTPHeaderField: "X-App-ID")
            ))
            return Self.bodies[url.path] ?? (404, #"{"error":{"code":"not_found","message":"No such route."}}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
