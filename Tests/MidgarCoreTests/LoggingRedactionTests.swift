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

    /// The redactor only runs an expression on a line that carries the sign of what it masks, so
    /// every line here is also put through all four expressions with no such check, and the two
    /// answers have to be the same line.
    @Test func masksExactlyWhatTheExpressionsAloneWould() {
        let hex31 = String(repeating: "a", count: 31)
        let hex32 = String(repeating: "f0", count: 16)
        let token39 = String(repeating: "x9", count: 19) + "x"
        let token40 = String(repeating: "x9", count: 20)
        let lines = [
            "", "plain words and nothing else", "bearer", "BEARER  abc.def", "a bbearer tok3n here",
            "the bearer of news", "mail a@b.co and c@d.io", "@ alone", "\(hex31) short", "\(hex32) long",
            "\(token39) short", "\(token40) long", "\(token40)==", "x-\(hex32)-y \(token40) z@y.fi Bearer q",
            "turns>6ms=" + String(repeating: "12/", count: 20), "ünïcode \(hex32) ünïcode",
            "session=3F2504E0-4F89-11D3-9A0C-0305E82C3301 rows=4",
        ]
        for line in lines {
            let alone = line
                .replacing(/(?i)(bearer\s+)[A-Za-z0-9._~+\/=-]+/) { "\($0.output.1)[REDACTED]" }
                .replacing(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, with: "[EMAIL]")
                .replacing(/[0-9a-fA-F]{32,}/, with: "[REDACTED]")
                .replacing(/(?=[A-Za-z0-9+\/_-]*[0-9+\/_-])[A-Za-z0-9+\/_-]{40,}={0,2}/, with: "[REDACTED]")
            #expect(MidgarLog.redacting(line) == alone)
        }
    }
}
