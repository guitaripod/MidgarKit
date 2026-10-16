import Foundation
import Testing
@testable import MidgarCore

@Suite struct IdentityWiringTests {
    @Test func identityAuthorizesTheAppClientAndNeverItself() async throws {
        let host = HTTPTestHost()
        host.enqueue([
            .json(201, sessionJSON(
                midgarId: "id-new", accessToken: freshToken(), refreshToken: "r", extra: ["credential": "CRED-W"]
            )),
            .json(200, #"{"ok":true}"#)
        ])
        let base = MidgarHTTPConfiguration(
            baseURL: host.baseURL,
            appID: "app-wiring",
            session: makeStubSession(),
            tokenProvider: { "would-deadlock" },
            userAgent: "Test/1",
            timeout: 5
        )
        let keychain = MidgarInMemoryKeychain()
        let identity = MidgarIdentity(
            httpConfiguration: base,
            bundleID: "com.example.wiring",
            keychain: keychain,
            attestation: MidgarUnsupportedAttestation(),
            logger: MidgarIdentityLogger(info: { _ in }, warning: { _ in })
        )
        let app = MidgarHTTPClient(configuration: identity.authorizing(base))

        struct Reply: Decodable, Sendable { let ok: Bool }
        let reply: Reply = try await app.send(MidgarRequest(service: "config", path: "flags"))

        #expect(reply.ok)
        let requests = host.requests
        #expect(requests.map(\.url.path) == ["/v1/identity/mint/unverified", "/v1/config/flags"])
        #expect(requests[0].headers["Authorization"] == nil)
        #expect(requests[0].headers["X-App-ID"] == "app-wiring")
        #expect(requests[1].headers["Authorization"] == "Bearer \(freshToken())")
        #expect(try keychain.read(.session(appID: "app-wiring")) != nil)
    }

    @Test func aFailingIdentityLeavesTheAppRequestUnauthorizedInsteadOfBlocked() async throws {
        let host = HTTPTestHost()
        host.enqueue([.failing(.notConnectedToInternet), .json(200, #"{"ok":true}"#)])
        let base = MidgarHTTPConfiguration(
            baseURL: host.baseURL, appID: "app-wiring", session: makeStubSession(), userAgent: "Test/1", timeout: 5
        )
        let identity = MidgarIdentity(
            httpConfiguration: base,
            bundleID: "com.example.wiring",
            keychain: MidgarInMemoryKeychain(),
            attestation: MidgarUnsupportedAttestation(),
            logger: MidgarIdentityLogger(info: { _ in }, warning: { _ in })
        )

        #expect(await identity.tokenProvider() == nil)
    }

    @Test func aUnauthorizedResponseKeepsItsCodeOnlyWhenTheRequestAsksFor() async throws {
        let host = HTTPTestHost()
        host.enqueue([
            .json(401, errorJSON("invalid_credential")),
            .json(401, errorJSON("invalid_credential"))
        ])
        let client = makeStubClient(host)

        let plain = await thrownError { try await client.sendRaw(MidgarRequest(service: "identity", path: "attach")) }
        let preserving = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "identity", path: "attach", preservesUnauthorizedCode: true))
        }

        #expect(plain == .unauthorized)
        #expect(preserving == .server(status: 401, code: "invalid_credential", message: "m"))
    }
}
