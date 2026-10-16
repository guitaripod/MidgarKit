import Foundation
import Testing
@testable import MidgarCore

private let okBody = StubReply.json(200, #"{"ok":true}"#)

private struct Ok: Decodable, Sendable {
    let ok: Bool
}

private struct Boom: Error {}

private actor TokenSource {
    private(set) var issued: [String] = []
    private(set) var invalidated: [String] = []
    private var counter = 0

    func next() -> String {
        counter += 1
        let token = "token-\(counter)"
        issued.append(token)
        return token
    }

    func invalidate(_ token: String) {
        invalidated.append(token)
    }
}

@Suite struct HTTPAuthorizationTests {
    @Test(arguments: [MidgarHTTPMethod.get, .post, .delete])
    func aRejectedTokenIsReplacedOnceAndTheRequestRepeats(method: MidgarHTTPMethod) async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("token_expired")), okBody])
        let source = TokenSource()
        let client = makeStubClient(
            host,
            tokenProvider: { await source.next() },
            tokenInvalidator: { await source.invalidate($0) }
        )

        let reply: Ok = try await client.send(MidgarRequest(service: "ledger", method: method))

        #expect(reply.ok)
        #expect(host.requests.map { $0.headers["Authorization"] } == ["Bearer token-1", "Bearer token-2"])
        #expect(await source.invalidated == ["token-1"])
    }

    @Test func invalidTokenIsRecoveredToo() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("invalid_token")), okBody])
        let source = TokenSource()
        let client = makeStubClient(host, tokenProvider: { await source.next() }, tokenInvalidator: { await source.invalidate($0) })

        let _: Ok = try await client.send(MidgarRequest(service: "ledger"))

        #expect(host.requests.count == 2)
    }

    @Test func aSecondRejectionIsThrownWithItsCode() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("token_expired")), .json(401, errorJSON("token_expired")), okBody])
        let source = TokenSource()
        let client = makeStubClient(host, tokenProvider: { await source.next() }, tokenInvalidator: { await source.invalidate($0) })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .unauthorized(code: "token_expired"))
        #expect(host.requests.count == 2)
    }

    @Test func otherUnauthorizedCodesAreNotRetried() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("forbidden")), okBody])
        let source = TokenSource()
        let client = makeStubClient(host, tokenProvider: { await source.next() }, tokenInvalidator: { await source.invalidate($0) })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .unauthorized(code: "forbidden"))
        #expect(host.requests.count == 1)
        #expect(await source.invalidated.isEmpty)
    }

    @Test func withoutAnInvalidatorARejectionIsThrown() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("token_expired")), okBody])
        let client = makeStubClient(host, tokenProvider: { "static" })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .unauthorized(code: "token_expired"))
        #expect(host.requests.count == 1)
    }

    @Test func aRequestSentWithoutATokenIsNotRetriedOnA401() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(401, errorJSON("invalid_token")), okBody])
        let source = TokenSource()
        let client = makeStubClient(host, tokenProvider: { nil }, tokenInvalidator: { await source.invalidate($0) })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .unauthorized(code: "invalid_token"))
        #expect(host.requests.count == 1)
    }

    @Test func aTokenProviderThatThrowsFailsTheRequestWithoutSendingIt() async throws {
        let host = HTTPTestHost()
        host.enqueue([okBody])
        let client = makeStubClient(host, tokenProvider: { throw Boom() })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .tokenUnavailable(isTransient: false))
        #expect(host.requests.isEmpty)
    }

    @Test func aTransientIdentityFailureIsReportedAsTransient() async throws {
        let host = HTTPTestHost()
        host.enqueue([okBody])
        let client = makeStubClient(host, tokenProvider: { throw MidgarIdentityError.credentialPendingSync })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .tokenUnavailable(isTransient: true))
        #expect(error?.isTransient == true)
        #expect(host.requests.isEmpty)
    }

    @Test func aCancelledTokenProviderCancelsTheRequest() async throws {
        let host = HTTPTestHost()
        let client = makeStubClient(host, tokenProvider: { throw CancellationError() })

        let error = await thrownError { try await client.sendRaw(MidgarRequest(service: "ledger")) }

        #expect(error == .cancelled)
    }

    @Test func neverRetriesSendsAnIdempotentMethodOnce() async throws {
        let host = HTTPTestHost()
        host.enqueue([.json(503, "{}"), okBody])
        let client = makeStubClient(host)

        let error = await thrownError {
            try await client.sendRaw(MidgarRequest(service: "identity", path: "me", method: .delete, neverRetries: true))
        }
        let plain = HTTPTestHost()
        plain.enqueue([.json(503, "{}"), okBody])
        let retried = await thrownError {
            try await makeStubClient(plain).sendRaw(MidgarRequest(service: "identity", path: "me", method: .delete))
        }

        #expect(error == .server(status: 503, code: nil, message: "HTTP 503"))
        #expect(host.requests.count == 1)
        #expect(retried == nil)
        #expect(plain.requests.count == 2)
    }

    @Test func theEnvelopeCodeSurvivesOn401And402And404And429() async throws {
        let cases: [(Int, MidgarHTTPError)] = [
            (401, .unauthorized(code: "c401")), (402, .paymentRequired(code: "c402")),
            (404, .notFound(code: "c404")), (429, .rateLimited(retryAfter: nil, code: "c429"))
        ]
        for (status, expected) in cases {
            let host = HTTPTestHost()
            host.enqueue([.json(status, errorJSON("c\(status)"))])
            let client = makeStubClient(host)

            let error = await thrownError {
                try await client.sendRaw(MidgarRequest(service: "ledger", method: .post, body: ["a": 1]))
            }

            #expect(error == expected)
            #expect(error?.serverCode == "c\(status)")
        }
    }
}
