import Foundation

/// Masks credentials and personal data before a message reaches os.Logger or the file.
enum LogRedactor {
    static func redact(_ text: String) -> String {
        text
            .replacing(/(?i)(bearer\s+)[A-Za-z0-9._~+\/=-]+/) { "\($0.output.1)[REDACTED]" }
            .replacing(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/, with: "[EMAIL]")
            .replacing(/[0-9a-fA-F]{32,}/, with: "[REDACTED]")
            .replacing(/(?=[A-Za-z0-9+\/_-]*[0-9+\/_-])[A-Za-z0-9+\/_-]{40,}={0,2}/, with: "[REDACTED]")
    }
}
