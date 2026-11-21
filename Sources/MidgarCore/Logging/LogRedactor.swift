import Foundation

/// Masks credentials and personal data before a message reaches os.Logger or the file.
///
/// Every logged line passes through here on the thread that logged it, so the common line, one with
/// nothing to mask, is answered by one pass over its bytes and never reaches a regular expression.
/// The expressions are built once: a regex literal is parsed again every time it is evaluated, which
/// cost a main thread milliseconds per line on an older phone.
enum LogRedactor {
    static func redact(_ text: String) -> String {
        let signs = Signs(text)
        guard signs.any else { return text }
        var masked = text
        if signs.bearer {
            masked = masked.replacing(Patterns.bearer) { "\($0.output.1)[REDACTED]" }
        }
        if signs.address { masked = masked.replacing(Patterns.email, with: "[EMAIL]") }
        if signs.hexRun { masked = masked.replacing(Patterns.hex, with: "[REDACTED]") }
        if signs.tokenRun { masked = masked.replacing(Patterns.token, with: "[REDACTED]") }
        return masked
    }

    private enum Patterns {
        nonisolated(unsafe) static let bearer = /(?i)(bearer\s+)[A-Za-z0-9._~+\/=-]+/
        nonisolated(unsafe) static let email = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
        nonisolated(unsafe) static let hex = /[0-9a-fA-F]{32,}/
        nonisolated(unsafe) static let token =
            /(?=[A-Za-z0-9+\/_-]*[0-9+\/_-])[A-Za-z0-9+\/_-]{40,}={0,2}/
    }

    /// What a line would have to contain for each expression to find anything in it: the word
    /// before a bearer token, an at sign, 32 hex digits in a row, 40 token characters in a row.
    private struct Signs {
        var bearer = false
        var address = false
        var hexRun = false
        var tokenRun = false

        var any: Bool { bearer || address || hexRun || tokenRun }

        init(_ text: String) {
            var hex = 0
            var token = 0
            var word = 0
            for byte in text.utf8 {
                let lower = byte | 0x20
                let isDigit = byte >= 0x30 && byte <= 0x39
                let isLetter = lower >= 0x61 && lower <= 0x7A
                if isDigit || (lower >= 0x61 && lower <= 0x66) {
                    hex += 1
                    if hex >= 32 { hexRun = true }
                } else {
                    hex = 0
                }
                if isDigit || isLetter || byte == 0x2B || byte == 0x2F || byte == 0x5F || byte == 0x2D {
                    token += 1
                    if token >= 40 { tokenRun = true }
                } else {
                    token = 0
                }
                if byte == 0x40 { address = true }
                word = Self.bearerProgress(word, lower)
                if word == Self.bearerWord.count {
                    bearer = true
                    word = 0
                }
            }
        }

        private static let bearerWord = Array("bearer".utf8)

        /// How much of the word is matched once `lower` follows `matched` letters of it.
        private static func bearerProgress(_ matched: Int, _ lower: UInt8) -> Int {
            if lower == bearerWord[matched] { return matched + 1 }
            return lower == bearerWord[0] ? 1 : 0
        }
    }
}
