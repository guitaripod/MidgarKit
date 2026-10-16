import Testing
@testable import MidgarCore

@Suite struct LoggingRedactionTests {
    @Test func masksBearerTokens() {
        let text = MidgarLog.redacting("GET /v1/me Authorization: Bearer eyJhbGciOi.payload-part_2~x=")
        #expect(text == "GET /v1/me Authorization: Bearer [REDACTED]")
    }

    @Test func masksLongHexStrings() {
        let token = String(repeating: "ab12", count: 16)
        #expect(MidgarLog.redacting("device \(token) registered") == "device [REDACTED] registered")
    }

    @Test func masksLongBase64ThatContainsDigits() {
        let secret = "QWxhZGRpbjpvcGVuIHNlc2FtZTEyMzQ1Njc4OTAxMjM0NTY3ODkw"
        #expect(MidgarLog.redacting("sent \(secret)") == "sent [REDACTED]")
    }

    @Test func masksEmailAddresses() {
        #expect(MidgarLog.redacting("user marcus@example.com signed in") == "user [EMAIL] signed in")
    }

    @Test func leavesOrdinaryTextAndIdentifiersAlone() {
        let plain = "loading 12 products for store Vivaldi-7 in 2 seconds"
        let uuid = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let shortHex = "deadbeef"
        let longWord = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
        #expect(MidgarLog.redacting(plain) == plain)
        #expect(MidgarLog.redacting(uuid) == uuid)
        #expect(MidgarLog.redacting(shortHex) == shortHex)
        #expect(MidgarLog.redacting(longWord) == longWord)
    }
}
